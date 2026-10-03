import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../pos/cart.dart';
import '../pos/pos_screen.dart';
import '../sales/send_sheet.dart';
import 'document_screen.dart';

/// Quotations, newest first.
final quotationsProvider = FutureProvider.autoDispose<List<QuotationRow>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.queries.quotations(firm.id);
});

/// Delivery challans, newest first.
final challansProvider = FutureProvider.autoDispose<List<QuotationRow>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.queries.challans(firm.id);
});

/// Prices given, or goods sent ahead of the bill, and what became of them.
///
/// A wholesaler quotes forty cartons on WhatsApp in the morning and the
/// retailer rings back at four to take them. The quotation is found here,
/// and the bill is made from it at the prices quoted.
///
/// With [challans], the same list for delivery challans: the van left with
/// the goods on Monday, and the bill is made from the challan on Saturday,
/// or the challan is cancelled when the goods come back.
class QuotationsScreen extends ConsumerWidget {
  const QuotationsScreen({super.key, this.challans = false});

  final bool challans;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final today = BusinessDate.now(ref.watch(appServicesProvider).clock);
    final provider = challans ? challansProvider : quotationsProvider;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(challans ? s.challansTitle : s.quotationsTitle),
      ),
      body: SafeArea(
        child: ref
            .watch(provider)
            .when(
              loading: () => const Padding(
                padding: EdgeInsets.all(BlTokens.space4),
                child: BlSkeletonList(rows: 4),
              ),
              error: (error, _) => BlError(
                title: s.commonSomethingWentWrong,
                message: '$error',
                retryLabel: s.actionRetry,
                onRetry: () => ref.invalidate(provider),
              ),
              data: (rows) => rows.isEmpty
                  ? challans
                        ? BlEmpty(
                            icon: Icons.assignment_turned_in_outlined,
                            title: s.challansEmpty,
                            message: s.challansEmptyHint,
                          )
                        : BlEmpty(
                            icon: Icons.request_quote_outlined,
                            title: s.quotationsEmpty,
                            message: s.quotationsEmptyHint,
                          )
                  : ListView(
                      padding: const EdgeInsets.all(BlTokens.space4),
                      children: [
                        for (final q in rows)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: BlTokens.space2,
                            ),
                            child: _QuotationTile(quotation: q, today: today),
                          ),
                      ],
                    ),
            ),
      ),
    );
  }
}

class _QuotationTile extends StatelessWidget {
  const _QuotationTile({required this.quotation, required this.today});

  final QuotationRow quotation;
  final BusinessDate today;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final q = quotation;
    final (String label, BlChipTone tone) = q.isVoid
        ? (s.challanCancelled, BlChipTone.neutral)
        : q.isBilled
        ? (s.quotationBilledAs(q.billedAs!), BlChipTone.good)
        : q.isChallan
        ? (s.challanUnbilled, BlChipTone.warn)
        : q.isExpiredOn(today)
        ? (s.quotationExpired, BlChipTone.neutral)
        : (s.quotationOpen, BlChipTone.warn);

    return BlCard(
      onTap: () => unawaited(
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _QuotationActions(quotation: q),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  q.partyName ?? s.posWalkInCustomer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                Text(
                  '${q.docNo} · ${q.date.value}',
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
                const SizedBox(height: BlTokens.space1),
                BlChip(label, tone: tone),
              ],
            ),
          ),
          const SizedBox(width: BlTokens.space2),
          BlMoney(q.total, size: 16),
        ],
      ),
    );
  }
}

class _QuotationActions extends ConsumerStatefulWidget {
  const _QuotationActions({required this.quotation});

  final QuotationRow quotation;

  @override
  ConsumerState<_QuotationActions> createState() => _QuotationActionsState();
}

class _QuotationActionsState extends ConsumerState<_QuotationActions> {
  bool _busy = false;
  String? _failure;

  /// Set by the first tap on the cancel button, which then asks again.
  bool _confirmingCancel = false;

  /// The goods on an unbilled challan came back: the challan is cancelled
  /// and they go back on the shelf.
  Future<void> _cancel() async {
    if (_busy) return;
    if (!_confirmingCancel) {
      setState(() => _confirmingCancel = true);
      return;
    }
    final s = AppStrings.of(context);
    setState(() {
      _busy = true;
      _failure = null;
    });
    final navigator = Navigator.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final services = ref.read(appServicesProvider);
      await services.voidDocument(
        services.actorNow(),
        documentId: widget.quotation.id,
        reason: s.challanCancelReason,
      );
      container.read(refreshTickProvider.notifier).update((n) => n + 1);
      navigator.pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = error is VoidRefused ? error.reason : '$error';
        });
      }
    }
  }

  /// This customer's other challans not yet billed (M25).
  List<QuotationRow> _others() {
    final q = widget.quotation;
    if (!q.isChallan || q.partyId == null) return const [];
    final all = ref.watch(challansProvider).valueOrNull ?? const [];
    return [
      for (final c in all)
        if (c.id != q.id && c.partyId == q.partyId && !c.isBilled && !c.isVoid)
          c,
    ];
  }

  /// Puts the quotation on the counter, at the prices quoted; with
  /// [together], this customer's other unbilled challans with it.
  Future<void> _bill({bool together = false}) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    if (!ref.read(cartProvider).isEmpty) {
      // Never over a bill somebody is in the middle of ringing.
      setState(() => _failure = s.quotationCounterBusy);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    final navigator = Navigator.of(context);
    try {
      final services = ref.read(appServicesProvider);
      final firm = (await ref.read(firmProvider.future))!;
      final q = widget.quotation;
      final also = together ? _others() : const <QuotationRow>[];
      final quoted = [
        for (final doc in [q, ...also])
          ...await services.queries.quotedLines(firm.id, doc.id),
      ];
      final lines = <(ItemSummary, QuotedLine)>[];
      for (final line in quoted) {
        final item = await services.queries.itemById(firm.id, line.itemId);
        if (item == null) {
          throw StateError(s.quotationItemGone);
        }
        lines.add((item, line));
      }
      final party = q.partyId == null
          ? null
          : await services.queries.partyById(firm.id, q.partyId!);
      // M54: what a challan sent free is billed as it went, whatever the
      // shop's schemes say today.
      final bonus = q.isChallan
          ? [
              for (final doc in [q, ...also])
                ...await services.queries.challanBonusLines(firm.id, doc.id),
            ]
          : null;
      ref
          .read(cartProvider.notifier)
          .loadQuotation(
            q,
            lines,
            party: party,
            alsoFrom: also,
            sentBonus: bonus, // M54
          );
      navigator.pop();
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const PosScreen()),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = error is StateError ? error.message : '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final q = widget.quotation;

    return Padding(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom: MediaQuery.viewPaddingOf(context).bottom + BlTokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            q.partyName ?? s.posWalkInCustomer,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: t.ink,
            ),
          ),
          Text(
            '${q.docNo} · ${q.total.amountOnly}'
            '${q.validUntil == null ? '' : ' · ${s.quotationValidUntil(q.validUntil!.value)}'}',
            style: TextStyle(fontSize: 14, color: t.inkMuted),
          ),
          const SizedBox(height: BlTokens.space4),
          // Sent as a bill is (M30): a PDF, a picture, or the customer's
          // WhatsApp chat with the quotation written out. Shared by every
          // document so a quotation is not the one that still only goes as
          // a file.
          SendButtons(
            documentId: q.id,
            onFailure: (message) {
              if (mounted) setState(() => _failure = message);
            },
          ),
          const SizedBox(height: BlTokens.space2),
          BlButton(
            label: s.documentView,
            icon: Icons.visibility_outlined,
            kind: BlButtonKind.ghost,
            onPressed: _busy
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          DocumentScreen(documentId: q.id, docNo: q.docNo),
                    ),
                  ),
          ),
          if (!q.isBilled && !q.isVoid) ...[
            const SizedBox(height: BlTokens.space2),
            BlButton(
              label: s.quotationBill,
              icon: Icons.point_of_sale_outlined,
              big: true,
              onPressed: _busy ? null : () => unawaited(_bill()),
            ),
          ],
          if (!q.isBilled && !q.isVoid && _others().isNotEmpty) ...[
            const SizedBox(height: BlTokens.space2),
            BlButton(
              label: s.challanBillAll(_others().length),
              icon: Icons.merge_type,
              kind: BlButtonKind.secondary,
              onPressed: _busy ? null : () => unawaited(_bill(together: true)),
            ),
          ],
          if (q.isChallan && !q.isBilled && !q.isVoid) ...[
            const SizedBox(height: BlTokens.space2),
            if (_confirmingCancel)
              Padding(
                padding: const EdgeInsets.only(bottom: BlTokens.space2),
                child: Text(
                  s.challanCancelConfirm(q.docNo),
                  style: TextStyle(fontSize: 14, color: t.ink),
                ),
              ),
            BlButton(
              label: s.challanCancel,
              icon: Icons.undo,
              kind: BlButtonKind.secondary,
              onPressed: _busy ? null : () => unawaited(_cancel()),
            ),
          ],
          if (_failure != null) ...[
            const SizedBox(height: BlTokens.space3),
            Text(_failure!, style: TextStyle(color: t.danger, fontSize: 14)),
          ],
        ],
      ),
    );
  }
}
