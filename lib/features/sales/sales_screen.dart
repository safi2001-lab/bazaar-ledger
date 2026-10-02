import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../app/paged.dart';
import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'receipt_screen.dart';
import 'send_sheet.dart';

/// The days the list can be narrowed to, as a shop says them.
enum SalesPeriod { all, today, thisWeek, thisMonth, lastMonth, chosen }

/// Every bill that was made, newest first, and the way to find one again
/// (M30).
///
/// It was a list and nothing more, so a bill from last month was found by
/// scrolling, and "send me that bill again" from a customer on the phone
/// meant asking them to wait. It now takes a bill number, a name, a phone
/// number or an amount, the period, and whether the bill is paid, on udhaar
/// or cancelled. Each narrowing is SQL under the paging cursor, never a
/// filter over the forty rows already on screen.
class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  SaleFilter _filter = SaleFilter.none;
  SalesPeriod _period = SalesPeriod.all;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// A query per keystroke is a query per letter of a customer's name, on
  /// the phone least able to afford it; the counter's own search waits the
  /// same quarter of a second.
  void _typed(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _filter = _filter.copyWith(query: text));
    });
  }

  Future<void> _choosePeriod(SalesPeriod period) async {
    final today = BusinessDate.now(ref.read(appServicesProvider).clock);
    if (period == SalesPeriod.chosen) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: _asDateTime(today),
        initialDateRange: _filter.from == null
            ? null
            : DateTimeRange(
                start: _asDateTime(_filter.from!),
                end: _asDateTime(_filter.to ?? today),
              ),
      );
      if (picked == null || !mounted) return;
      setState(() {
        _period = period;
        _filter = _filter.between(_asDate(picked.start), _asDate(picked.end));
      });
      return;
    }
    final (from, to) = salesPeriodRange(period, today);
    setState(() {
      _period = period;
      _filter = _filter.between(from, to);
    });
  }

  void _clear() {
    _debounce?.cancel();
    _search.clear();
    setState(() {
      _period = SalesPeriod.all;
      _filter = SaleFilter.none;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final provider = pagedSalesProvider(_filter);
    final sales = ref.watch(provider);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.salesTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BlTokens.space4,
                BlTokens.space3,
                BlTokens.space4,
                0,
              ),
              child: BlField(
                controller: _search,
                label: s.salesSearch,
                hint: s.salesSearchHint,
                prefix: const Icon(Icons.search),
                textInputAction: TextInputAction.search,
                onChanged: _typed,
                suffix: _search.text.isEmpty
                    ? null
                    : BlIconButton(
                        icon: Icons.close,
                        label: s.salesClearSearch,
                        onPressed: () {
                          _search.clear();
                          _typed('');
                          setState(() {});
                        },
                      ),
              ),
            ),
            _ChipRow(
              children: [
                for (final period in SalesPeriod.values)
                  ChoiceChip(
                    selected: _period == period,
                    label: Text(
                      period == SalesPeriod.chosen &&
                              _period == SalesPeriod.chosen
                          ? s.salesPeriodRange(
                              _filter.from?.value ?? '',
                              _filter.to?.value ?? '',
                            )
                          : _periodName(s, period),
                    ),
                    onSelected: (_) => unawaited(_choosePeriod(period)),
                  ),
              ],
            ),
            _ChipRow(
              children: [
                for (final standing in SaleStanding.values)
                  ChoiceChip(
                    selected: _filter.standing == standing,
                    label: Text(_standingName(s, standing)),
                    onSelected: (_) => setState(
                      () => _filter = _filter.copyWith(standing: standing),
                    ),
                  ),
              ],
            ),
            Expanded(
              child: sales.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(BlTokens.space4),
                  child: BlSkeletonList(),
                ),
                error: (error, _) => Center(
                  child: BlError(
                    title: s.commonSomethingWentWrong,
                    message: '$error',
                    retryLabel: s.actionRetry,
                    onRetry: () => ref.invalidate(provider),
                  ),
                ),
                data: (page) {
                  final rows = page.items;
                  if (rows.isEmpty && _filter.isNone) {
                    return Center(
                      child: BlEmpty(
                        title: s.salesEmpty,
                        message: s.salesEmptyHint,
                        icon: Icons.receipt_long_outlined,
                      ),
                    );
                  }
                  if (rows.isEmpty) {
                    // Said as a search that found nothing, with the way back
                    // to every bill, never as a shop with no bills.
                    return Center(
                      child: BlEmpty(
                        title: s.salesNoneFound,
                        message: s.salesNoneFoundHint,
                        icon: Icons.search_off_outlined,
                        action: BlButton(
                          label: s.salesClearFilters,
                          kind: BlButtonKind.secondary,
                          onPressed: _clear,
                        ),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => ref.bumpRefresh(),
                    // The list was a hard limit of sixty. A shop three years
                    // in could not scroll to last month.
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        final at = n.metrics;
                        if (at.pixels >= at.maxScrollExtent * 0.8) {
                          unawaited(ref.read(provider.notifier).more());
                        }
                        return false;
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.all(BlTokens.space4),
                        itemCount: rows.length,
                        itemBuilder: (context, i) => SaleRowTile(row: rows[i]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _periodName(AppStrings s, SalesPeriod period) =>
      switch (period) {
        SalesPeriod.all => s.salesPeriodAll,
        SalesPeriod.today => s.salesPeriodToday,
        SalesPeriod.thisWeek => s.salesPeriodWeek,
        SalesPeriod.thisMonth => s.salesPeriodMonth,
        SalesPeriod.lastMonth => s.salesPeriodLastMonth,
        SalesPeriod.chosen => s.salesPeriodPick,
      };

  static String _standingName(AppStrings s, SaleStanding standing) =>
      switch (standing) {
        SaleStanding.all => s.salesStandingAll,
        SaleStanding.paid => s.salesStandingPaid,
        SaleStanding.udhaar => s.salesStandingUdhaar,
        SaleStanding.cancelled => s.salesStandingCancelled,
      };

  static DateTime _asDateTime(BusinessDate d) =>
      DateTime(d.year, d.month, d.day);

  /// The day the picker's calendar showed, as the shop's business date. The
  /// picker's dates are midnight local, so their own fields are the day.
  static BusinessDate _asDate(DateTime d) => BusinessDate(
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}',
  );
}

/// The first and last day of [period], counted from [today]; both null for
/// every day there is.
///
/// A week starts on Monday, as the shop's own week does: Friday is a half
/// day for prayers, not the end of anything. "This week", "this month" and
/// "today" end today; last month ends on its own last day.
(BusinessDate?, BusinessDate?) salesPeriodRange(
  SalesPeriod period,
  BusinessDate today,
) {
  BusinessDate firstOf(int year, int month) => BusinessDate(
    '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-01',
  );
  return switch (period) {
    SalesPeriod.all || SalesPeriod.chosen => (null, null),
    SalesPeriod.today => (today, today),
    SalesPeriod.thisWeek => (
      today.addDays(
        1 - DateTime.utc(today.year, today.month, today.day).weekday,
      ),
      today,
    ),
    SalesPeriod.thisMonth => (firstOf(today.year, today.month), today),
    SalesPeriod.lastMonth => (
      today.month == 1
          ? firstOf(today.year - 1, 12)
          : firstOf(today.year, today.month - 1),
      firstOf(today.year, today.month).addDays(-1),
    ),
  };
}

/// A row of chips that scrolls sideways rather than wrapping: two rows of
/// filters is already as much of the screen as a list should give up, and at
/// 200% text a wrapped row would take the rest of it.
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        BlTokens.space4,
        BlTokens.space2,
        BlTokens.space4,
        0,
      ),
      child: Row(
        children: [
          for (final chip in children)
            Padding(
              padding: const EdgeInsets.only(right: BlTokens.space2),
              child: chip,
            ),
        ],
      ),
    );
  }
}

/// One bill in a list. Shared by the sales list and the home screen so the two
/// can never drift apart.
///
/// A tap opens the bill. The send button on the row — or a long press
/// anywhere on it — sends it again without opening it (M30): PDF, picture,
/// the customer's WhatsApp chat, or the printer.
class SaleRowTile extends StatelessWidget {
  const SaleRowTile({super.key, required this.row});

  final SaleListRow row;

  void _send(BuildContext context) => unawaited(
    showSendSheet(
      context,
      documentId: row.id,
      docNo: row.docNo,
      offerPrint: true,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;

    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space2),
      child: GestureDetector(
        onLongPress: () => _send(context),
        child: BlCard(
          padding: const EdgeInsets.only(
            left: BlTokens.space4,
            top: BlTokens.space3,
            bottom: BlTokens.space3,
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ReceiptScreen(documentId: row.id, docNo: row.docNo),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            row.docNo,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: row.isVoid ? t.inkFaint : t.ink,
                              decoration: row.isVoid
                                  ? TextDecoration.lineThrough
                                  : null,
                              fontFeatures: BlTokens.tabular,
                            ),
                          ),
                        ),
                        if (row.isVoid) ...[
                          const SizedBox(width: BlTokens.space2),
                          Flexible(
                            child: BlChip(s.salesVoided, tone: BlChipTone.bad),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: BlTokens.space1),
                    Text(
                      // The date as well as the time: a found bill is as
                      // often last month's as this morning's.
                      '${row.partyName ?? s.posWalkInCustomer} · '
                      '${row.dateLocal} ${row.timeLabel} · '
                      '${s.posItemsInCart(row.lineCount)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: t.inkMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: BlTokens.space3),
              // Given a share of the row and scaled down inside it, never cut:
              // at 200% text a six-figure total would otherwise run under the
              // send button, or off the card.
              Flexible(
                flex: 2,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      BlMoney(row.total, size: 17, semanticPrefix: row.docNo),
                      const SizedBox(height: BlTokens.space1),
                      if (row.isPaid)
                        BlChip(s.salesPaid, tone: BlChipTone.good)
                      else
                        BlChip(
                          s.salesUdhaar(row.balance.amountOnly),
                          tone: BlChipTone.warn,
                        ),
                    ],
                  ),
                ),
              ),
              BlIconButton(
                icon: Icons.share_outlined,
                label: s.sendAction,
                onPressed: () => _send(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
