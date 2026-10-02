import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Taking back a line sold in maunds at a discount, from the app (M57).
///
/// The sheet used to count in kilos and print the bill's unit beside them:
/// one maund sold was offered back as "40 maund baqi", plus took back one
/// kilo, and the total beside it was the list price per maund for that
/// kilo — Rs 5,000 for a kilo of a Rs 4,500 maund. It now counts in the
/// unit the line was sold in and shows what was paid for it.
void main() {
  testWidgets('the sheet offers a maund back by the maund, at what was paid', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final atta = await _sellAMaund(app);

    await _openBill(tester);
    await tester.tap(find.byTooltip('Wapas lein'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 maund baqi'), findsOneWidget);
    expect(find.textContaining('40 maund'), findsNothing);

    await tester.tap(find.byTooltip('Shamil karein').first);
    await tester.pumpAndSettle();
    expect(
      find.text('Rs 4,500.00'),
      findsOneWidget,
      reason: 'the return total is the Rs 4,500 paid, not Rs 5,000',
    );

    await typeInto(tester, 'Wajah', 'Keera laga hua');
    await tapText(tester, 'Wapsi save karein');
    await tester.pumpAndSettle();

    final returns = await app.rowsOf(
      'SELECT d.total_paisa, l.qty_thousandths, l.base_qty_thousandths, '
      'l.unit_code_snapshot FROM documents d '
      'JOIN document_lines l ON l.document_id = d.id '
      "WHERE d.doc_type = 'sale_return'",
    );
    expect(returns.single['total_paisa'], 450000);
    expect(returns.single['qty_thousandths'], 1000);
    expect(returns.single['base_qty_thousandths'], 40000);
    expect(returns.single['unit_code_snapshot'], 'maund');

    final stock = await app.rowsOf(
      'SELECT COALESCE(SUM(qty_delta_thousandths), 0) AS q FROM stock_ledger '
      "WHERE item_id = '$atta'",
    );
    expect(stock.single['q'], 200000, reason: 'all forty kilos are back');

    final firmId = app.services.identity!.firmId;
    final party = (await app.services.queries.searchParties(firmId)).first;
    expect(
      (await app.services.queries.partyById(firmId, party.id))!.balance,
      Money.zero,
      reason: 'the customer owed Rs 4,500 and was credited a different sum',
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

/// One maund of atta at Rs 5,000 less 10%, on udhaar, off 200 kilos.
Future<String> _sellAMaund(Harness app) async {
  final firm = app.services.identity!.firmId;
  final actor = app.services.actorNow();
  final units = await app.services.queries.units(firm);
  final kg = units.firstWhere((u) => u.code == 'kg');
  final maund = units.firstWhere((u) => u.code == 'maund');

  final itemId = await app.services.catalogue.addItem(
    actor,
    ItemDraft(
      name: 'Atta Chakki',
      baseUnitId: kg.id,
      saleRate: Rate.rupees(125),
      openingStock: Qty.units(200),
      openingRate: Rate.rupees(110),
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
          itemName: 'Atta Chakki',
          qty: Qty.one,
          baseQty: Qty.units(40),
          unitId: maund.id,
          unitCode: 'maund',
          rate: Rate.rupees(5000),
          discountBp: 1000,
        ),
      ],
      tenders: const [],
    ),
  );
  return itemId;
}
