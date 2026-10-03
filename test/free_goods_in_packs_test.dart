import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// A supplier's bonus typed beside a delivery counted in packs (M43 with
/// M45).
///
/// The free box counts in the unit chip the shopkeeper has chosen, but
/// typing "10 ctn 5" moves the paid line to pieces — and the free goods are
/// written as a row of their own in the line's unit. Before the two met,
/// one free carton on such a line went on the shelf as 24 pieces but was
/// written as "1 pcs muft", and the delivery disagreed with the shelf.
void main() {
  testWidgets('a free carton on a delivery typed 10 ctn 5 is written as 24 '
      'pieces, and the shelf holds 269', (tester) async {
    final app = await Harness.startWithShop(tester);
    final gala = await _gala(app);
    await _openDelivery(tester, app);

    await tester.tap(find.textContaining('carton ·'));
    await tester.pumpAndSettle();
    await typeInto(tester, 'Tadaad (carton)', '10 ctn 5');
    await typeInto(tester, 'Kharid qeemat', '9800');
    await typeInto(tester, 'Muft / bonus (carton)', '1');
    await tester.tap(find.text('Cheez shamil karein').last);
    await tester.pumpAndSettle();
    await tapText(tester, 'Kharidari save karein');
    await tester.pumpAndSettle();

    final rows = await app.rowsOf(
      'SELECT dl.is_free_item f, dl.unit_code_snapshot u, '
      'dl.qty_thousandths q, dl.base_qty_thousandths b FROM document_lines dl '
      'JOIN documents d ON d.id = dl.document_id '
      "WHERE d.doc_type = 'purchase_bill' ORDER BY dl.line_no",
    );
    expect(rows, [
      {'f': 0, 'u': 'pcs', 'q': 245000, 'b': 245000},
      {'f': 1, 'u': 'pcs', 'q': 24000, 'b': 24000},
    ]);
    expect(await _onHand(app, gala), 269000);
  });
}

Future<void> _openDelivery(WidgetTester tester, Harness app) async {
  await app.services.catalogue.addParty(
    app.services.actorNow(),
    const PartyDraft(name: 'Peek Freans Depot', partyType: 'supplier'),
  );
  await tester.pumpAndSettle();
  await tapText(tester, 'Kharidari');
  await tapText(tester, 'Nayi kharidari');
  await tapText(tester, 'Supplier chunein');
  await tapText(tester, 'Peek Freans Depot');
  await tapText(tester, 'Cheez shamil karein');
  await typeInto(tester, 'Talash karein', 'Gala');
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tapText(tester, 'Gala Biscuit');
}

Future<String> _gala(Harness app) async {
  final units = await app.services.queries.units(app.services.identity!.firmId);
  String unit(String code) => units.firstWhere((u) => u.code == code).id;
  return app.services.catalogue.addItem(
    app.services.actorNow(),
    ItemDraft(
      name: 'Gala Biscuit',
      baseUnitId: unit('pcs'),
      saleRate: Rate.rupees(40),
      openingRate: Rate.rupees(30),
      packs: [ItemPack(unitId: unit('carton'), size: Qty.units(24))],
    ),
  );
}

Future<int> _onHand(Harness app, String itemId) async =>
    (await app.rowsOf(
          'SELECT COALESCE(SUM(qty_delta_thousandths), 0) q FROM stock_ledger '
          "WHERE item_id = '$itemId'",
        )).single['q']!
        as int;
