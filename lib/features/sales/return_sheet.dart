import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// Taking goods back off a bill.
///
/// ## Why not just cancel the bill
///
/// Because a customer who bought five things and brought one back still
/// bought four. Cancelling would take the other four off the shop's books
/// while the customer keeps them, and the tax on them is owed either way.
///
/// ## What is left, per line
///
/// Shown next to every line, counted through the returns already recorded
/// against this bill. A shopkeeper should never be able to type a quantity
/// the save then refuses — being told no after choosing is how a counter
/// queue turns into an argument.
///
/// It can still go stale: a second till taking the same tin back between this
/// sheet opening and Save. The writer re-reads inside its transaction, so the
/// write is right and the screen was optimistic, which is the correct
/// direction for that error to run.
Future<bool> showReturnSheet(
  BuildContext context, {
  required String documentId,
  required String docNo,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ReturnSheet(documentId: documentId, docNo: docNo),
  );
  return saved ?? false;
}

class _ReturnSheet extends ConsumerStatefulWidget {
  const _ReturnSheet({required this.documentId, required this.docNo});

  final String documentId;
  final String docNo;

  @override
  ConsumerState<_ReturnSheet> createState() => _SheetState();
}

class _SheetState extends ConsumerState<_ReturnSheet> {
  final _reason = TextEditingController();
  final _refund = TextEditingController();

  /// Thousandths chosen per document line.
  final _chosen = <String, int>{};

  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _reason.dispose();
    _refund.dispose();
    super.dispose();
  }

  Money _total(List<SoldLine> lines) => Money.sum([
    for (final line in lines)
      if ((_chosen[line.documentLineId] ?? 0) > 0)
        line.rate.amountFor(Qty.raw(_chosen[line.documentLineId]!)),
  ]);

  Future<void> _save(List<SoldLine> lines) async {
    if (_busy) return;
    final s = AppStrings.of(context);

    final picked = [
      for (final entry in _chosen.entries)
        if (entry.value > 0)
          ReturnLineDraft(documentLineId: entry.key, qty: Qty.raw(entry.value)),
    ];
    if (picked.isEmpty) {
      setState(() => _failure = s.returnPickSomething);
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => _failure = s.returnReasonRequired);
      return;
    }

    setState(() {
      _busy = true;
      _failure = null;
    });

    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final refund = Money.tryParse(_refund.text) ?? Money.zero;

    try {
      final recorded = await services.recordReturn(
        services.actorNow(),
        ReturnDraft(
          originalDocumentId: widget.documentId,
          lines: picked,
          reason: _reason.text.trim(),
          refundNow: refund,
          paymentAccountId: refund.isPositive
              ? (await services.queries.paymentAccounts(
                  services.identity!.firmId,
                )).firstWhere((a) => a.isDefault).id
              : null,
          // A van phone takes goods back onto the van (M27).
          locationCode: await services.counterLocation(),
        ),
      );
      container.bumpRefresh();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.returnDone(recorded.docNo))));
      Navigator.of(context).pop(true);
    } on ReturnRefused catch (refusal) {
      // Its own sentence, not a stack trace. Every refusal here names a
      // quantity or an account the shopkeeper can do something about.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = refusal.reason;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final lines = ref.watch(returnableLinesProvider(widget.documentId));

    return Padding(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom:
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.viewPaddingOf(context).bottom +
            BlTokens.space4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.returnTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
            Text(
              widget.docNo,
              style: TextStyle(fontSize: 14, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space3),

            lines.when(
              loading: () => const BlSkeletonList(rows: 2),
              error: (error, _) =>
                  BlError(title: s.commonSomethingWentWrong, message: '$error'),
              data: (rows) {
                final left = rows
                    .where((l) => l.returnable.isPositive)
                    .toList();
                if (left.isEmpty) {
                  return BlEmpty(
                    icon: Icons.check_circle_outline,
                    title: s.returnNothingLeft,
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final line in left)
                      _LineRow(
                        line: line,
                        chosen: _chosen[line.documentLineId] ?? 0,
                        onChanged: (v) => setState(() {
                          _chosen[line.documentLineId] = v;
                          _failure = null;
                        }),
                      ),
                    const SizedBox(height: BlTokens.space3),
                    BlField(controller: _reason, label: s.returnReason),
                    const SizedBox(height: BlTokens.space2),
                    BlField(
                      controller: _refund,
                      label: s.returnRefundNow,
                      numeric: true,
                      onChanged: (_) => setState(() => _failure = null),
                    ),
                    const SizedBox(height: BlTokens.space3),
                    BlCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.returnTotal,
                              style: TextStyle(fontSize: 14, color: t.inkMuted),
                            ),
                          ),
                          BlMoney(_total(left), size: 18, withSymbol: true),
                        ],
                      ),
                    ),
                    if (_failure != null) ...[
                      const SizedBox(height: BlTokens.space3),
                      Text(
                        _failure!,
                        style: TextStyle(fontSize: 13, color: t.danger),
                      ),
                    ],
                    const SizedBox(height: BlTokens.space4),
                    BlButton(
                      label: s.returnSave,
                      icon: Icons.check,
                      big: true,
                      busy: _busy,
                      onPressed: _busy ? null : () => unawaited(_save(left)),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// One line, with how much of it is still returnable.
class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.chosen,
    required this.onChanged,
  });

  final SoldLine line;
  final int chosen;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final max = line.returnable.inThousandths;

    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space2),
      child: BlCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.itemName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                  Text(
                    s.returnLeft('${line.returnable.display} ${line.unitCode}'),
                    style: TextStyle(fontSize: 12, color: t.inkMuted),
                  ),
                ],
              ),
            ),
            // Whole units up and down. A kiryana return is a tin or a packet;
            // a keyboard here would be four taps where two will do, and would
            // let a shopkeeper type past what is left.
            BlIconButton(
              icon: Icons.remove_circle_outline,
              label: s.actionDelete,
              onPressed: chosen <= 0
                  ? null
                  : () => onChanged((chosen - 1000).clamp(0, max)),
            ),
            SizedBox(
              width: 44,
              child: Text(
                Qty.raw(chosen).display,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                  fontFeatures: BlTokens.tabular,
                ),
              ),
            ),
            BlIconButton(
              icon: Icons.add_circle_outline,
              label: s.actionAdd,
              onPressed: chosen >= max
                  ? null
                  : () => onChanged((chosen + 1000).clamp(0, max)),
            ),
          ],
        ),
      ),
    );
  }
}
