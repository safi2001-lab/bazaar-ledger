import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import 'text_rasteriser.dart';

/// What this counter prints on, or null if nobody has chosen yet.
final printerSettingsProvider = FutureProvider<PrinterSettings?>((ref) async {
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return null;
  final services = ref.watch(appServicesProvider);
  final identity = services.identity;
  if (identity == null) return null;
  return services.printing.settings(identity.firmId, identity.deviceId);
});

/// Which transports can actually be used on this device.
///
/// Asked rather than assumed. A phone with no Bluetooth radio, or one where
/// the permission was refused, should be told so on the setup screen instead
/// of being offered a choice that fails at the counter with a customer
/// waiting.
final availableTransportsProvider = FutureProvider<Set<String>>((ref) async {
  final services = ref.watch(appServicesProvider);
  final usable = <String>{};
  for (final transport in services.printing.transports) {
    if (await transport.isAvailable) usable.add(transport.kind);
  }
  return usable;
});

/// The receipt bytes for one bill at the configured width, or null if there is
/// no printer yet.
final receiptBytesProvider = FutureProvider.family<List<int>?, String>((
  ref,
  documentId,
) async {
  final settings = await ref.watch(printerSettingsProvider.future);
  if (settings == null) return null;
  final services = ref.watch(appServicesProvider);
  final identity = services.identity;
  if (identity == null) return null;
  final receipt = await services.queries.receiptFor(
    identity.firmId,
    documentId,
  );
  if (receipt == null) return null;
  return services.receipts.toThermalBytes(
    receipt,
    paper: settings.paper,
    drawn: await _drawUnprintable(services.receipts, receipt, settings.paper),
    // Only on a sale that actually took cash. A drawer that clicks on a
    // card payment is a drawer somebody unplugs.
    openDrawer:
        settings.openDrawerOnCash && receipt.tenders.any((t) => t.isCash),
  );
});

/// Pictures of the lines the printer's own font cannot say.
///
/// Empty for the overwhelming majority of receipts: the template is Roman
/// Urdu in Latin script and every money row is digits, so nothing needs
/// drawing until the shop types its own name, an item or a customer in Urdu
/// script. When it does, that line arrives as a raster image rather than as
/// the row of question marks the encoder would otherwise substitute.
///
/// Whole lines, not fragments. An item name padded out to a right-aligned
/// price is one string containing an RTL run and an LTR one, and deciding
/// what order those come out in is the bidirectional algorithm's job — done
/// once, by the text engine, on the composed line.
Future<Map<String, MonoBitmap>> _drawUnprintable(
  ReceiptRenderer renderer,
  ReceiptData receipt,
  ReceiptPaper paper,
) async {
  return drawUnprintableLines(renderer, receipt, paper);
}

/// A ruler and a sample money row, for finding out how wide the paper is.
///
/// The ruler is exactly [PrinterSettings.columns] characters wide, marked
/// every tenth column. If it fits on one line, the setting is right; if it
/// wraps, the printer is narrower than the app thinks and every total on every
/// receipt will wrap the same way.
///
/// This is the only reliable detector. ESC/POS has no query for column width,
/// and 80mm printers ship as both 42 and 48 depending on the ROM font, so two
/// machines that look identical on a shelf take different receipts. A
/// shopkeeper looking at paper beats any amount of probing.
List<int> testPrintBytes(PrinterSettings settings) {
  final columns = settings.columns;
  final ruler = StringBuffer();
  for (var i = 1; i <= columns; i++) {
    ruler.write(i % 10 == 0 ? '${(i ~/ 10) % 10}' : '.');
  }

  final escpos = EscPos()
    ..initialise()
    ..codePage(0)
    ..font(EscPosFont.a)
    ..align(EscPosAlign.centre)
    ..line('BAZAAR LEDGER')
    ..align(EscPosAlign.left)
    ..feed()
    ..line('$columns columns')
    ..line(ruler.toString())
    ..feed()
    // A real money row at the real width, right-flushed the way every total on
    // a receipt is. A ruler proves the width; this proves it looks right.
    ..line(_row('Chawal 5 kg', 'Rs 2,450.00', columns))
    ..line(_row('TOTAL', 'Rs 2,450.00', columns))
    ..feed(2)
    ..cut();
  return escpos.bytes;
}

/// Left text, right amount, padded to exactly [columns].
String _row(String left, String right, int columns) {
  final room = columns - right.length;
  final label = left.length > room ? left.substring(0, room) : left;
  return label.padRight(room) + right;
}

/// Every print already attempted for one bill.
///
/// The receipt screen uses it for one thing only: whether the button says
/// Print or Reprint. A shopkeeper who has already printed a bill and taps
/// again should be able to see that they are asking for a second copy.
final printHistoryProvider =
    FutureProvider.family<List<PrintJobRecord>, String>((
      ref,
      documentId,
    ) async {
      final services = ref.watch(appServicesProvider);
      final identity = services.identity;
      if (identity == null) return const [];
      return services.printing.historyFor(identity.firmId, documentId);
    });
