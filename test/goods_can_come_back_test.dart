import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Taking goods back, from the app.
///
/// A customer who bought five things and brought one back still bought four.
/// Cancelling the bill would take the other four off the shop's books while
/// the customer keeps them, so a return is a different action and needs its
/// own way in.
void main() {
  testWidgets('a posted bill offers to take goods back', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _sell(app);

    await _openBill(tester);

    expect(find.byTooltip('Wapas lein'), findsOneWidget);
  });

  testWidgets('one tin off a bill for five reaches the database', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _sell(app);

    await _openBill(tester);
    await _takeBack(tester, taps: 1, reason: 'Packet phata hua tha');

    final returns = await app.rowsOf(
      'SELECT doc_no, total_paisa FROM documents '
      "WHERE doc_type = 'sale_return'",
    );
    expect(
      returns,
      hasLength(1),
      reason:
          'the Save button did nothing. Every printer artefact in this '
          'repository was in exactly that state for two commits.',
    );
    expect(returns.single['total_paisa'], 15000);

    // Five sold, one back: four gone off the shelf.
    final stock = await app.rowsOf(
      'SELECT COALESCE(SUM(qty_delta_thousandths), 0) AS b FROM stock_ledger',
    );
    expect(stock.single['b'], 8000);
  });

  testWidgets('the sheet shows what is still returnable', (tester) async {
    // A shopkeeper should never be able to type a quantity the save refuses.
    final app = await Harness.startWithShop(tester);
    await _sell(app);

    await _openBill(tester);
    await tester.tap(find.byTooltip('Wapas lein'));
    await tester.pumpAndSettle();

    expect(find.textContaining('5 pcs baqi'), findsOneWidget);
  });

  testWidgets('and counts down after an earlier visit', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _sell(app);

    await _openBill(tester);
    await _takeBack(tester, taps: 2, reason: 'Do packet kharab');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Wapas lein'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('3 pcs baqi'),
      findsOneWidget,
      reason:
          'the sheet is offering back stock an earlier visit already took, '
          'and the save will refuse what the shopkeeper just chose',
    );
  });

  testWidgets('a return with nothing chosen is refused in words', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _sell(app);

    await _openBill(tester);
    await tester.tap(find.byTooltip('Wapas lein'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Wapsi save karein');
    await tester.pumpAndSettle();

    expect(find.text('Kam az kam ek cheez chunein'), findsOneWidget);
    expect(await app.rowsOf('SELECT id FROM doc_links'), isEmpty);
  });

  testWidgets('a return with no reason is refused in words', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _sell(app);

    await _openBill(tester);
    await tester.tap(find.byTooltip('Wapas lein'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Shamil karein').first);
    await tester.pumpAndSettle();
    await tapText(tester, 'Wapsi save karein');
    await tester.pumpAndSettle();

    expect(find.text('Wajah likhna zaroori hai'), findsOneWidget);
    expect(await app.rowsOf('SELECT id FROM doc_links'), isEmpty);
  });

  testWidgets('a bill with nothing left to return says so', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _sell(app);

    await _openBill(tester);
    await _takeBack(tester, taps: 5, reason: 'Sab wapas');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Wapas lein'));
    await tester.pumpAndSettle();

    expect(find.text('Is bill se sab kuch wapas ho chuka'), findsOneWidget);
  });

  testWidgets('the credit comes off the khata', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _sell(app);
    final firmId = app.services.identity!.firmId;
    final partyId = (await app.services.queries.searchParties(firmId)).first.id;

    expect(
      (await app.services.queries.partyById(firmId, partyId))!.balance,
      const Money.rupees(750),
    );

    await _openBill(tester);
    await _takeBack(tester, taps: 1, reason: 'Kharab');

    expect(
      (await app.services.queries.partyById(firmId, partyId))!.balance,
      const Money.rupees(600),
      reason: 'the customer is still being chased for goods they gave back',
    );
  });
}

Future<void> _openBill(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Farokht');
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('INV-').first);
  await tester.pumpAndSettle();
}

/// Opens the sheet, taps + [taps] times, and saves.
Future<void> _takeBack(
  WidgetTester tester, {
  required int taps,
  required String reason,
}) async {
  await tester.tap(find.byTooltip('Wapas lein'));
  await tester.pumpAndSettle();
  for (var i = 0; i < taps; i++) {
    await tester.tap(find.byTooltip('Shamil karein').first);
    await tester.pumpAndSettle();
  }
  await typeInto(tester, 'Wajah', reason);
  await tapText(tester, 'Wapsi save karein');
  await tester.pumpAndSettle();
}

/// Five tins on udhaar, off a shelf of twelve.
Future<void> _sell(Harness app) async {
  final firm = app.services.identity!.firmId;
  final actor = app.services.actorNow();
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');

  final itemId = await app.services.catalogue.addItem(
    actor,
    ItemDraft(
      name: 'Chawal Basmati',
      baseUnitId: pcs.id,
      saleRate: Rate.rupees(150),
      openingStock: Qty.units(12),
      openingRate: Rate.rupees(90),
    ),
  );
  final partyId = await app.services.catalogue.addParty(
    actor,
    const PartyDraft(name: 'Rashid Traders', partyType: 'customer'),
  );

  await app.services.postSale(
    actor,
    SaleDraft(
      partyId: partyId,
      lines: [
        SaleLineDraft(
          itemId: itemId,
          itemName: 'Chawal Basmati',
          qty: Qty.units(5),
          baseQty: Qty.units(5),
          unitId: pcs.id,
          unitCode: 'pcs',
          rate: Rate.rupees(150),
        ),
      ],
      tenders: const [],
    ),
  );
}
