import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../audit/history_screen.dart';
import '../printing/bill_copy.dart';
import '../printing/printing_providers.dart';
import 'bill_again.dart';
import 'correct_bill_sheet.dart';
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
///
/// ## The sheet (M51)
///
/// Above the buttons, which sheet goes out: the original, a duplicate, a
/// triplicate, or the transporter's copy with no prices. The preview is that
/// sheet, dressed as the shop's design dresses it — the khata block, the
/// shop's own footer — because the preview is the paper.
///
/// ## Again, and put right (M36)
///
/// Under the bar's ⋮: "Isi tarah ka naya bill" puts this bill's lines and
/// customer on the counter as a new bill (a cancelled bill too), and
/// "Ghalti theek karein" cancels a standing bill and opens its copy there to
/// be corrected. A bill that replaced another, or was replaced, says which
/// above the paper, a tap from the other.
class ReceiptScreen extends ConsumerStatefulWidget {
  const ReceiptScreen({
    super.key,
    required this.documentId,
    required this.docNo,
  });

  final String documentId;
  final String docNo;

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  /// The sheet chosen; null prints the bill as it always printed.
  ReceiptCopy? _copy;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final documentId = widget.documentId;
    final docNo = widget.docNo;
    final sheet = (documentId: documentId, copy: _copy);
    final bill = ref.watch(billSheetProvider(sheet));
    final status = ref.watch(documentStatusProvider(documentId));
    final services = ref.watch(appServicesProvider);
    final standing = status.valueOrNull == 'posted';
    // Ringing it again needs only the counter; putting it right cancels it,
    // so it needs what a cancel needs as well (M36). A role that may do
    // neither is not shown a menu that only ever says no.
    final mayCopy = services.can(Permission.sell) && status.valueOrNull != null;
    final mayCorrect =
        standing &&
        services.can(Permission.sell) &&
        services.can(Permission.voidDocuments);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(s.receiptTitle(docNo)),
        actions: [
          // Everything that ever happened to this bill: made, printed,
          // paid, returned, cancelled and why (M42). Hidden from a role
          // that may not read the activity log.
          HistoryButton(
            record: RecordRef.document(documentId),
            label: docNo,
          ),
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
          // Behind the dots rather than two more icons: at 200% text a
          // phone's bar has room for the bill's number and two buttons, and
          // the number is what the shopkeeper is checking.
          if (mayCopy || mayCorrect)
            PopupMenuButton<_More>(
              tooltip: s.billMoreActions,
              icon: const Icon(Icons.more_vert),
              onSelected: (choice) => unawaited(switch (choice) {
                _More.copy => billAgain(
                  context,
                  ref,
                  documentId: documentId,
                  docNo: docNo,
                ),
                _More.correct => showCorrectBillSheet(
                  context,
                  documentId: documentId,
                  docNo: docNo,
                ),
              }),
              itemBuilder: (_) => [
                if (mayCopy)
                  PopupMenuItem(
                    value: _More.copy,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.copy_all_outlined),
                      title: Text(s.copyAction),
                    ),
                  ),
                if (mayCorrect)
                  PopupMenuItem(
                    value: _More.correct,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.published_with_changes_outlined,
                      ),
                      title: Text(s.correctAction),
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: bill.when(
          // The last sheet stays on screen while the next one is read, so
          // tapping a different copy does not blank the page.
          skipLoadingOnReload: true,
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 6),
          ),
          error: (error, _) => Center(
            child: BlError(
              title: s.commonSomethingWentWrong,
              message: '$error',
              retryLabel: s.actionRetry,
              onRetry: () => ref.invalidate(billSheetProvider(sheet)),
            ),
          ),
          data: (prepared) {
            if (prepared == null) {
              return Center(child: BlEmpty(title: s.commonNothingSaved));
            }
            final data = prepared.receipt;
            return Column(
              children: [
                _BillLinksLine(documentId: documentId),
                // A cancelled bill is shown marked, as it is sent marked
                // (M30); the thermal paper of it still prints as it did.
                Expanded(
                  child: PaperPreview(
                    data: status.valueOrNull == 'void'
                        ? data.copyWith(isCancelled: true)
                        : data,
                  ),
                ),
                _Actions(
                  documentId: documentId,
                  bill: prepared,
                  copy: _copy,
                  onCopy: (copy) => setState(() => _copy = copy),
                ),
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

    // The paper's own size, whatever the app's (M36). Forty-eight columns
    // are forty-eight columns: the app's text size (M56) and the phone's
    // own made the preview grow until it scrolled sideways, which is not
    // what the paper looks like, and the paper is what this is showing.
    return MediaQuery.withNoTextScaling(
      child: SingleChildScrollView(
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
      ),
    );
  }
}

/// What the bar's dots offer (M36).
enum _More { copy, correct }

/// "Replaces INV-…" on a corrected bill, "Replaced by INV-…" on the one it
/// put right (M36), each a tap from the other. Nothing at all on a bill
/// that is neither, which is almost every bill.
class _BillLinksLine extends ConsumerWidget {
  const _BillLinksLine({required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final links = ref.watch(billLinksProvider(documentId)).valueOrNull;
    if (links == null || links.isEmpty) return const SizedBox.shrink();

    Widget line(LinkedBill bill, String words, IconData icon) => Padding(
      padding: const EdgeInsets.fromLTRB(
        BlTokens.space4,
        BlTokens.space2,
        BlTokens.space4,
        0,
      ),
      child: BlCard(
        padding: const EdgeInsets.symmetric(
          horizontal: BlTokens.space3,
          vertical: BlTokens.space2,
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ReceiptScreen(documentId: bill.id, docNo: bill.docNo),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: t.accent),
            const SizedBox(width: BlTokens.space2),
            Expanded(
              child: Text(
                words,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: t.ink,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: t.inkFaint),
          ],
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (links.replaces case final old?)
          line(old, s.billReplaces(old.docNo), Icons.history),
        if (links.replacedBy case final next?)
          line(
            next,
            next.isVoid
                ? s.billReplacedByVoid(next.docNo)
                : s.billReplacedBy(next.docNo),
            Icons.published_with_changes_outlined,
          ),
      ],
    );
  }
}

class _Actions extends ConsumerStatefulWidget {
  const _Actions({
    required this.bill,
    required this.documentId,
    required this.copy,
    required this.onCopy,
  });

  final PreparedBill bill;
  final String documentId;
  final ReceiptCopy? copy;
  final ValueChanged<ReceiptCopy?> onCopy;

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
      await printBill(
        context,
        documentId: widget.documentId,
        copy: widget.copy,
      );
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.bill.sendsGoods) ...[
              CopyChooser(
                value: widget.copy,
                originalPrinted: alreadyPrinted,
                offerTransporter: true,
                onChanged: widget.onCopy,
              ),
              if (widget.copy == ReceiptCopy.transporter) ...[
                const SizedBox(height: BlTokens.space2),
                TransportLine(
                  documentId: widget.documentId,
                  transport: widget.bill.transport,
                ),
              ],
              const SizedBox(height: BlTokens.space3),
            ],
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
            SendButtons(documentId: widget.documentId, copy: widget.copy),
          ],
        ),
      ),
    );
  }
}
