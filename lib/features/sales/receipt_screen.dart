import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../printing/printing_providers.dart';
import 'print_bill.dart';
import 'return_sheet.dart';
import 'send_sheet.dart';
import 'void_bill_sheet.dart';

/// One bill, exactly as it will print.
///
/// The preview is the same 48-column layout the thermal printer receives, so
/// what a shopkeeper checks on screen is what comes out of the machine —
/// including the column width, which is a per-printer setting because ESC/POS
/// has no query for it and 80 mm printers ship as both 42 and 48.
///
/// Three things happen here: look at it, print it, and send it — as a PDF,
/// as a picture, or into the customer's WhatsApp chat (M30). The same screen
/// opens after a sale and from the bill's row in the sales list, so a bill
/// can be sent again whenever it is wanted, not only while the customer is
/// still at the counter.
class ReceiptScreen extends ConsumerWidget {
  const ReceiptScreen({
    super.key,
    required this.documentId,
    required this.docNo,
  });

  final String documentId;
  final String docNo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final receipt = ref.watch(receiptProvider(documentId));
    final status = ref.watch(documentStatusProvider(documentId));

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(s.receiptTitle(docNo)),
        actions: [
          // Offered only while the bill is still standing. A cancel button on
          // a cancelled bill is an action that can only fail, and a shopkeeper
          // who taps it learns to distrust the whole screen.
          // Offered before Cancel, because it is the commoner of the two by
          // a long way: a customer bringing one thing back is an everyday
          // event, and a bill that should never have existed is not.
          if (status.valueOrNull == 'posted' &&
              ref.watch(appServicesProvider).can(Permission.takeReturns))
            BlIconButton(
              icon: Icons.assignment_return_outlined,
              label: s.returnAction,
              onPressed: () => unawaited(
                showReturnSheet(context, documentId: documentId, docNo: docNo),
              ),
            ),
          // Not offered to a role that may not cancel a bill; the service
          // refuses it anyway, but a button that only ever says no is noise.
          if (status.valueOrNull == 'posted' &&
              ref.watch(appServicesProvider).can(Permission.voidDocuments))
            BlIconButton(
              icon: Icons.block,
              label: s.voidAction,
              onPressed: () => unawaited(
                showVoidBillSheet(
                  context,
                  documentId: documentId,
                  docNo: docNo,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: receipt.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 6),
          ),
          error: (error, _) => Center(
            child: BlError(
              title: s.commonSomethingWentWrong,
              message: '$error',
              retryLabel: s.actionRetry,
              onRetry: () => ref.invalidate(receiptProvider(documentId)),
            ),
          ),
          data: (data) {
            if (data == null) {
              return Center(child: BlEmpty(title: s.commonNothingSaved));
            }
            return Column(
              children: [
                // A cancelled bill is shown marked, as it is sent marked
                // (M30); the thermal paper of it still prints as it did.
                Expanded(
                  child: PaperPreview(
                    data: status.valueOrNull == 'void'
                        ? data.copyWith(isCancelled: true)
                        : data,
                  ),
                ),
                _Actions(documentId: documentId, data: data),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The 48-column layout, rendered on screen in a monospaced face.
///
/// Deliberately not a prettier "screen version" of the same bill. A separate
/// on-screen layout is a second implementation that drifts, and the first
/// anybody notices is when a customer's printed copy disagrees with what the
/// shopkeeper was shown.
///
/// Public since M30: a delivery, a quotation or a challan opened from its
/// list is shown on the same paper.
class PaperPreview extends ConsumerWidget {
  const PaperPreview({super.key, required this.data});

  final ReceiptData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final text = services.receipts
        .toPreview(data, paper: ReceiptPaper.mm80)
        .join('\n');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(BlTokens.space4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: BlTokens.space4,
            vertical: BlTokens.space5,
          ),
          decoration: BoxDecoration(
            color: t.surfaceRaised,
            borderRadius: BorderRadius.circular(BlTokens.radiusSm),
            border: Border.all(color: t.line),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Courier New', 'Roboto Mono'],
                fontSize: 12,
                height: 1.35,
                color: t.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Actions extends ConsumerStatefulWidget {
  const _Actions({required this.data, required this.documentId});

  final ReceiptData data;
  final String documentId;

  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

class _ActionsState extends ConsumerState<_Actions> {
  bool _busy = false;

  /// Sends the bill to the configured printer, once. The printing itself is
  /// [printBill], shared with the sales list's row so there is one print
  /// path; this keeps the second tap out while the first is on its way.
  Future<void> _print() async {
    // First statement, before any await. A disabled button only disables on
    // the next build, so two taps in one frame both reach here -- and this is
    // the one path in the app where that costs a customer a second receipt.
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await printBill(context, documentId: widget.documentId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final printer = ref.watch(printerSettingsProvider);
    final history = ref.watch(printHistoryProvider(widget.documentId));
    final alreadyPrinted =
        history.valueOrNull?.any((r) => r.status == PrintJobStatus.printed) ??
        false;

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.line)),
      ),
      padding: const EdgeInsets.all(BlTokens.space4),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (printer.valueOrNull == null)
              Padding(
                padding: const EdgeInsets.only(bottom: BlTokens.space3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.print_disabled_outlined,
                      size: 15,
                      color: t.inkFaint,
                    ),
                    const SizedBox(width: BlTokens.space2),
                    Expanded(
                      child: Text(
                        s.receiptNoPrinter,
                        style: TextStyle(fontSize: 12, color: t.inkFaint),
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: BlTokens.space3),
                child: BlButton(
                  label: alreadyPrinted ? s.receiptReprint : s.receiptPrint,
                  icon: Icons.print_outlined,
                  big: true,
                  busy: _busy,
                  onPressed: _busy ? null : _print,
                ),
              ),
            SendButtons(documentId: widget.documentId),
          ],
        ),
      ),
    );
  }
}
