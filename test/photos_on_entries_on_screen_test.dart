import 'dart:typed_data';

import 'package:bazaar_ledger/features/sales/receipt_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// A photograph of the paper on the entry it belongs to (M60), from the
/// screens.
///
/// The picker is a system dialog and cannot be driven from a host test, as
/// M2's item picture found; the photographs are put on through the same
/// service the strip calls, and everything either side of that — the strip
/// on the page, the photograph full size, taking it off, the bin, bringing
/// it back — is driven by taps.
void main() {
  testWidgets('a photo of the bijli bill shows on its expense and opens full '
      'size, saying who put it on', (tester) async {
    final app = await Harness.startWithShop(tester);
    final rent = await _spend(app);
    final id = await _photograph(app, 'documents', rent.documentId);
    await tester.pumpAndSettle();

    await tapText(tester, 'Kharcha');
    await tapText(tester, 'August ka kiraya');
    expect(find.text('Kaghaz ki tasveerein · 1'), findsOneWidget);
    final thumb = find.byKey(ValueKey('entry-photo-$id'));
    expect(thumb, findsOneWidget);

    await tester.ensureVisible(thumb);
    await tester.pumpAndSettle();
    await tester.tap(thumb);
    await tester.pumpAndSettle();
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.textContaining('Malik Sahib ne lagayi'), findsOneWidget);
  });

  testWidgets('a photo taken off its entry is asked about first, and waits '
      'in the bin', (tester) async {
    final app = await Harness.startWithShop(tester);
    final rent = await _spend(app);
    final id = await _photograph(app, 'documents', rent.documentId);
    await tester.pumpAndSettle();

    await tapText(tester, 'Kharcha');
    await tapText(tester, 'August ka kiraya');
    final thumb = find.byKey(ValueKey('entry-photo-$id'));
    await tester.ensureVisible(thumb);
    await tester.pumpAndSettle();
    await tester.tap(thumb);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tasveer hatayein'));
    await tester.pumpAndSettle();
    expect(find.textContaining("'Hatayi hui cheezein' mein rahegi"), findsOne);
    await tapText(tester, 'Haan');
    await settleReal(tester, until: find.textContaining('Tasveer hata di'));

    expect(await app.services.photos.of('documents', rent.documentId), isEmpty);
    expect(find.byKey(ValueKey('entry-photo-$id')), findsNothing);
    expect((await app.services.photos.removed()).single.id, id);
  });

  testWidgets('a photo in the bin says whose hand took it off, and comes '
      'back to its entry', (tester) async {
    final app = await Harness.startWithShop(tester);
    final rent = await _spend(app);
    final id = await _photograph(app, 'documents', rent.documentId);
    await app.services.photos.remove(id);
    await tester.pumpAndSettle();

    await _openHidden(tester);
    expect(find.text('Tasveerein'.toUpperCase()), findsOneWidget);
    expect(find.text('${rent.docNo} ki tasveer'), findsOneWidget);
    expect(find.textContaining('Malik Sahib ne hataya ·'), findsOneWidget);
    expect(
      find.textContaining('Yahan se kuch khud nahi mitta'),
      findsOneWidget,
    );
    await tapButton(tester, 'Wapas layein');

    expect(find.text('Kuch hataya nahi gaya'), findsOneWidget);
    expect(
      await app.services.photos.of('documents', rent.documentId),
      hasLength(1),
    );
  });

  testWidgets('a sale bill carries the strip above its paper, and a khata '
      'says its papers stay on this phone', (tester) async {
    final app = await Harness.startWithShop(tester);
    final rashid = await app.seedParty(name: 'Rashid Traders');
    final bill = await _sell(app, rashid);
    final id = await _photograph(app, 'documents', bill.documentId);
    await tester.pumpAndSettle();

    await tapText(tester, 'Gahak');
    await tapText(tester, 'Rashid Traders');
    await tapText(tester, bill.docNo);
    expect(find.byType(ReceiptScreen), findsOneWidget);
    expect(find.byKey(ValueKey('entry-photo-$id')), findsOneWidget);
    expect(find.text('Tasveer lein'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Gahak ki tafseel'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('sirf isi phone par rehti hain'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Kaghaz ki tasveerein'), findsOneWidget);
  });
}

Future<void> _openHidden(WidgetTester tester) async {
  await openSettings(tester);
  await tester.scrollUntilVisible(find.text('Hatayi hui cheezein'), 200);
  await tapText(tester, 'Hatayi hui cheezein');
}

Future<String> _cash(Harness app) async =>
    (await app.services.queries.paymentAccounts(
      app.services.identity!.firmId,
    )).firstWhere((a) => a.isDefault).id;

Future<RecordedExpense> _spend(Harness app) async => app.services.recordExpense(
  app.services.actorNow(),
  ExpenseDraft(
    accountSystemKey: 'rent',
    amount: const Money.rupees(4000),
    note: 'August ka kiraya',
    paymentAccountId: await _cash(app),
  ),
);

Future<PostedSale> _sell(Harness app, String partyId) async {
  final itemId = await app.seedItem(name: 'Cooking Oil', rupees: 3000);
  final pcs = (await app.services.queries.units(
    app.services.identity!.firmId,
  )).firstWhere((u) => u.code == 'pcs');
  return app.services.postSale(
    app.services.actorNow(),
    SaleDraft(
      partyId: partyId,
      lines: [
        SaleLineDraft(
          itemId: itemId,
          itemName: 'Cooking Oil',
          qty: Qty.units(1),
          baseQty: Qty.units(1),
          unitId: pcs.id,
          unitCode: 'pcs',
          rate: Rate.rupees(3000),
        ),
      ],
    ),
  );
}

/// Puts a photograph of a ruled page on a row, through the service the
/// strip itself calls once the picker hands it the bytes.
Future<String> _photograph(Harness app, String table, String id) {
  final page = img.Image(width: 300, height: 400);
  img.fill(page, color: img.ColorRgb8(236, 230, 214));
  for (var y = 20; y < 400; y += 24) {
    img.drawLine(
      page,
      x1: 20,
      y1: y,
      x2: 280,
      y2: y,
      color: img.ColorRgb8(30, 40, 120),
    );
  }
  return app.services.photos.add(
    ownerTable: table,
    ownerId: id,
    kind: EntryPhotoKind.receipt,
    source: Uint8List.fromList(img.encodeJpg(page)),
    fileName: 'parchi.jpg',
  );
}
