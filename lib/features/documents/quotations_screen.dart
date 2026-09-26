import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../pos/cart.dart';
import '../pos/pos_screen.dart';
import '../printing/pdf_font.dart';
import '../sales/receipt_file_name.dart';

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

/// Prices given, and what became of them.
///
/// A wholesaler quotes forty cartons on WhatsApp in the morning and the
/// retailer rings back at four to take them. The quotation is found here,
/// and the bill is made from it at the prices quoted.
class QuotationsScreen extends ConsumerWidget {
  const QuotationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final today = BusinessDate.now(ref.watch(appServicesProvider).clock);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.quotationsTitle)),
      body: SafeArea(
        child: ref
            .watch(quotationsProvider)
            .when(
              loading: () => const Padding(
                padding: EdgeInsets.all(BlTokens.space4),
                child: BlSkeletonList(rows: 4),
              ),
              error: (error, _) => BlError(
                title: s.commonSomethingWentWrong,
                message: '$error',
                retryLabel: s.actionRetry,
                onRetry: () => ref.invalidate(quotationsProvider),
              ),
              data: (rows) => rows.isEmpty
                  ? BlEmpty(
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
    final (String label, BlChipTone tone) = q.isBilled
        ? (s.quotationBilledAs(q.billedAs!), BlChipTone.good)
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

  Future<void> _share() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final services = ref.read(appServicesProvider);
      final firm = await ref.read(firmProvider.future);
      final data = await services.queries.receiptFor(
        firm!.id,
        widget.quotation.id,
      );
      if (data == null) throw StateError(widget.quotation.docNo);
      final bytes = await services.receipts.toPdf(
        data,
        unicodeFont: await PdfUnicodeFont.bytes(),
      );
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}${Platform.pathSeparator}'
        '${receiptFileName(widget.quotation.docNo)}',
      );
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: widget.quotation.docNo,
        ),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _failure = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Puts the quotation on the counter, at the prices quoted.
  Future<void> _bill() async {
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
      final quoted = await services.queries.quotedLines(firm.id, q.id);
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
      ref.read(cartProvider.notifier).loadQuotation(q, lines, party: party);
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
          BlButton(
            label: s.quotationSharePdf,
            icon: Icons.picture_as_pdf_outlined,
            kind: BlButtonKind.secondary,
            busy: _busy,
            onPressed: _busy ? null : () => unawaited(_share()),
          ),
          if (!q.isBilled) ...[
            const SizedBox(height: BlTokens.space2),
            BlButton(
              label: s.quotationBill,
              icon: Icons.point_of_sale_outlined,
              big: true,
              onPressed: _busy ? null : () => unawaited(_bill()),
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
