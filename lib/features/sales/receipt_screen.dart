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
import '../printing/pdf_font.dart';
import '../printing/printing_providers.dart';
import 'receipt_file_name.dart';
import 'return_sheet.dart';
import 'void_bill_sheet.dart';

/// One bill, exactly as it will print.
///
/// The preview is the same 48-column layout the thermal printer receives, so
/// what a shopkeeper checks on screen is what comes out of the machine —
/// including the column width, which is a per-printer setting because ESC/POS
/// has no query for it and 80 mm printers ship as both 42 and 48.
///
/// Three things happen here: look at it, print it, and send
/// the PDF.
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
                Expanded(child: _Paper(data: data)),
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
class _Paper extends ConsumerWidget {
  const _Paper({required this.data});

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

  Future<void> _sharePdf() async {
    // First statement. Setting `_busy` inside the `setState` below let two
    // taps in one frame both through, and each one renders a PDF and opens
    // its own share sheet.
    if (_busy) return;
    final s = AppStrings.of(context);
    setState(() => _busy = true);
    try {
      final services = ref.read(appServicesProvider);
      final bytes = await services.receipts.toPdf(
        widget.data,
        // A PDF carries its own fonts: it is read on the customer's phone,
        // not this one, so there is no system fallback to fall back to.
        // Without this the shop's name is simply absent from the copy they
        // are handed.
        unicodeFont: await PdfUnicodeFont.bytes(),
      );
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}${Platform.pathSeparator}'
        '${receiptFileName(widget.data.docNo)}',
      );
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: widget.data.docNo,
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${s.commonSomethingWentWrong}: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sends the bill to the configured printer, once.
  ///
  /// The job key is deterministic and carries the column width, so a reprint
  /// at a different width is honestly a different piece of paper rather than
  /// the same job asked for twice. [copyIndex] is what a person increments
  /// when they have looked at the paper and decided they want another.
  Future<void> _print({int copyIndex = 1}) async {
    // First statement, before any await. A disabled button only disables on
    // the next build, so two taps in one frame both reach here -- and this is
    // the one path in the app where that costs a customer a second receipt.
    if (_busy) return;
    final s = AppStrings.of(context);
    setState(() => _busy = true);

    final messenger = ScaffoldMessenger.of(context);
    try {
      final settings = await ref.read(printerSettingsProvider.future);
      if (settings == null) {
        messenger.showSnackBar(SnackBar(content: Text(s.receiptNoPrinter)));
        return;
      }
      final bytes = await ref.read(
        receiptBytesProvider(widget.documentId).future,
      );
      if (bytes == null) {
        messenger.showSnackBar(SnackBar(content: Text(s.receiptNoPrinter)));
        return;
      }

      final services = ref.read(appServicesProvider);
      final result = await services.printing.print(
        actor: services.actorNow(),
        settings: settings,
        jobKey: printJobKey(
          documentId: widget.documentId,
          revision: 1,
          columns: settings.columns,
          copyIndex: copyIndex,
        ),
        bytes: bytes,
        documentId: widget.documentId,
        copyIndex: copyIndex,
      );
      if (!mounted) return;

      // Re-read the log, or the button keeps saying Print after a successful
      // one and a shopkeeper has no way to tell the first attempt worked.
      ref.invalidate(printHistoryProvider(widget.documentId));

      switch (result.outcome) {
        case PrintOutcome.printed:
          messenger.showSnackBar(SnackBar(content: Text(s.printerDone)));
        case PrintOutcome.notSent:
          messenger.showSnackBar(SnackBar(content: Text(s.printerNotSent)));
        case PrintOutcome.partial:
          // Paper has already moved. Never offered as a retry -- the
          // shopkeeper is told to look at what came out.
          messenger.showSnackBar(SnackBar(content: Text(s.printerPartial)));
        case PrintOutcome.unknown:
          // The app was killed mid-print. Nobody can say whether paper moved,
          // so the only honest thing is to ask the person holding it.
          await _askWhetherItPrinted(copyIndex: copyIndex);
      }
    } on Object catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${s.commonSomethingWentWrong}: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The question a killed print leaves behind.
  ///
  /// There is no correct automatic answer here. The row says `sending`, which
  /// means the app died holding the job, and on a Transsion ROM that happens
  /// after the printer has already taken part of the receipt. Only the person
  /// looking at the paper knows.
  Future<void> _askWhetherItPrinted({required int copyIndex}) async {
    final s = AppStrings.of(context);
    final again = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(s.printerUnknownAsk),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.printerPrintAgain),
          ),
        ],
      ),
    );
    if (again != true || !mounted) return;
    // A new copy index, so it is recorded as the deliberate second print it
    // is rather than overwriting the record of the first.
    setState(() => _busy = false);
    await _print(copyIndex: copyIndex + 1);
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
            BlButton(
              label: s.receiptSharePdf,
              icon: Icons.picture_as_pdf_outlined,
              kind: BlButtonKind.secondary,
              busy: _busy,
              onPressed: _busy ? null : _sharePdf,
            ),
          ],
        ),
      ),
    );
  }
}
