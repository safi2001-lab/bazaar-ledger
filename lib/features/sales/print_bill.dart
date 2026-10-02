import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../l10n/app_strings.dart';
import '../printing/printing_providers.dart';

/// Sends one bill to the configured printer, once.
///
/// Moved here from the receipt screen unchanged (M30), so the sales list can
/// print a bill from its row through exactly the same door. Two copies of
/// this would be two print paths, and the one that drifted would be the one
/// that hands a customer two receipts.
///
/// The job key is deterministic and carries the column width, so a reprint
/// at a different width is honestly a different piece of paper rather than
/// the same job asked for twice. [copyIndex] is what a person increments
/// when they have looked at the paper and decided they want another.
///
/// The caller guards against a second tap before the first is through; the
/// queue also refuses a job already on its way, but a screen that lets the
/// tap through shows a spinner for a print that will never come.
///
/// ## Choosing the sheet (M51)
///
/// [copy] is the sheet somebody picked: the original, a duplicate, a
/// triplicate, or the transporter's copy with no prices. Null prints the
/// bill as it always printed, as copy one, so asking twice still hands the
/// customer one receipt. The original is copy one too, and the same job: an
/// original asked for after one was printed is not printed again. Every
/// other sheet is a new piece of paper by somebody's deliberate choice, so
/// it takes the next copy number this bill has not used.
Future<void> printBill(
  BuildContext context, {
  required String documentId,
  int copyIndex = 1,
  ReceiptCopy? copy,
}) async {
  final s = AppStrings.of(context);
  final messenger = ScaffoldMessenger.of(context);
  // Held across the awaits, not looked up after them: the screen that asked
  // may be gone by the time the printer answers.
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    final settings = await container.read(printerSettingsProvider.future);
    if (settings == null) {
      messenger.showSnackBar(SnackBar(content: Text(s.receiptNoPrinter)));
      return;
    }
    final services = container.read(appServicesProvider);
    final bytes = await receiptBytes(
      services,
      settings,
      documentId,
      copy: copy,
    );
    if (bytes == null) {
      messenger.showSnackBar(SnackBar(content: Text(s.receiptNoPrinter)));
      return;
    }
    if (copy != null && !(copy == ReceiptCopy.original && copyIndex == 1)) {
      copyIndex = await nextCopyIndex(services, documentId, atLeast: copyIndex);
    }

    final result = await services.printing.print(
      actor: services.actorNow(),
      settings: settings,
      jobKey: printJobKey(
        documentId: documentId,
        revision: 1,
        columns: settings.columns,
        copyIndex: copyIndex,
      ),
      bytes: bytes,
      documentId: documentId,
      copyIndex: copyIndex,
    );

    // Re-read the log, or the button keeps saying Print after a successful
    // one and a shopkeeper has no way to tell the first attempt worked.
    container.invalidate(printHistoryProvider(documentId));

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
        if (!context.mounted) return;
        await _askWhetherItPrinted(
          context,
          documentId: documentId,
          copyIndex: copyIndex,
          copy: copy,
        );
    }
  } on Object catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text('${s.commonSomethingWentWrong}: $error')),
    );
  }
}

/// The first copy number [documentId] has not printed under, and never less
/// than [atLeast] or two: copy one is the original's.
Future<int> nextCopyIndex(
  AppServices services,
  String documentId, {
  int atLeast = 2,
}) async {
  final identity = services.identity;
  final history = identity == null
      ? const <PrintJobRecord>[]
      : await services.printing.historyFor(identity.firmId, documentId);
  var next = atLeast < 2 ? 2 : atLeast;
  for (final job in history) {
    if (job.copyIndex >= next) next = job.copyIndex + 1;
  }
  return next;
}

/// The question a killed print leaves behind.
///
/// There is no correct automatic answer here. The row says `sending`, which
/// means the app died holding the job, and on a Transsion ROM that happens
/// after the printer has already taken part of the receipt. Only the person
/// looking at the paper knows.
Future<void> _askWhetherItPrinted(
  BuildContext context, {
  required String documentId,
  required int copyIndex,
  ReceiptCopy? copy,
}) async {
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
  if (again != true || !context.mounted) return;
  // A new copy index, so it is recorded as the deliberate second print it
  // is rather than overwriting the record of the first. The same sheet as
  // was asked for: the person holding the paper decided it did not come out.
  await printBill(
    context,
    documentId: documentId,
    copyIndex: copyIndex + 1,
    copy: copy,
  );
}
