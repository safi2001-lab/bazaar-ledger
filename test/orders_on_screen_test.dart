import 'dart:io';

import 'package:bazaar_ledger/app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'support/harness.dart';

/// Orders on the screen (M41): a purchase order written, received at the
/// door with its rate checked; a customer's order with an advance taken to
/// the counter and billed; the counter's shortage list; and what to order,
/// one purchase order per supplier in one tap.
final _sheet = _FakeShareSheet();

void main() {
  setUpAll(() => SharePlatform.instance = _sheet);
  setUp(_sheet.texts.clear);

  testWidgets('a purchase order is written, received at another rate, and '
      'the rate is flagged before the delivery is saved', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Atta 10kg', rupees: 600);
    await _supplier(app, 'Haji Flour Mills');

    await tapText(tester, 'Order');
    await tapText(tester, 'Purchase order (PO)');
    expect(find.text('Abhi koi PO nahi'), findsOneWidget);
    await tapText(tester, 'Nayi PO');
    await tapText(tester, 'Supplier chunein');
    await tapText(tester, 'Haji Flour Mills');
    await _addItem(tester, 'Atta', 'Atta 10kg', qty: '10', rate: '500');
    await tapText(tester, 'Kal');
    await tapButton(tester, 'Order save karein');

    final po = await app.rowsOf(
      'SELECT id, doc_no, total_paisa, terms FROM documents '
      "WHERE doc_type = 'purchase_order'",
    );
    expect(po.single['total_paisa'], 500000);
    expect(po.single['terms'], startsWith('Expected by '));
    expect(await app.countIn('journal_entries'), 1, reason: 'opening only');
    expect(find.text('Khula'), findsOneWidget);

    await tapButton(tester, 'Maal aa gaya');
    expect(find.text('PO ${po.single['doc_no']} ke khilaf'), findsOneWidget);
    expect(find.text('10 pcs x 500.00'), findsOneWidget);

    // The supplier's bill says Rs 520 a bag.
    await tapText(tester, 'Atta 10kg');
    await typeInto(tester, 'Rate', '520');
    await tapButton(tester, 'Save karein');
    expect(find.text('Rate PO se mukhtalif: 520.00 vs 500.00'), findsOneWidget);
    // The order's "saved" note sits over the save bar until it goes.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tapButton(tester, 'Kharidari save karein');

    final link = await app.rowsOf(
      'SELECT l.from_document_id, d.total_paisa FROM doc_links l '
      'JOIN documents d ON d.id = l.to_document_id '
      "WHERE d.doc_type = 'purchase_bill'",
    );
    expect(link.single['from_document_id'], po.single['id']);
    expect(link.single['total_paisa'], 520000);
    expect(find.text('Sab aa gaya'), findsOneWidget);
    expect(find.text('Aaya 10, baqi 0 pcs'), findsOneWidget);
  });

  testWidgets('a customer\'s order with an advance goes to the counter, is '
      'billed on udhaar, and the advance settles part of the bill', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Ghee 1kg', rupees: 500);
    final aslam = await app.seedParty(name: 'Aslam Store');

    await tapText(tester, 'Order');
    await tapText(tester, 'Gahak ke order');
    await tapText(tester, 'Naya gahak order');
    await tapText(tester, 'Gahak chunein');
    await tapText(tester, 'Aslam Store');
    await _addItem(tester, 'Ghee', 'Ghee 1kg', qty: '10');
    await typeInto(tester, 'Advance (marzi se)', '2000');
    await tapButton(tester, 'Order save karein');

    final advance = await app.rowsOf(
      'SELECT p.amount_paisa, p.reference, d.doc_no FROM payments p '
      "JOIN documents d ON d.doc_type = 'sale_order'",
    );
    expect(advance.single['amount_paisa'], 200000);
    expect(advance.single['reference'], advance.single['doc_no']);
    expect(find.text('Advance Rs 2,000.00'), findsOneWidget);

    await tapButton(tester, 'Counter par bill banayein');
    await tapButton(tester, 'Paisay lein');
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();
    await tapButton(tester, 'Save karein');

    final bill = await app.rowsOf(
      'SELECT total_paisa, paid_paisa, balance_paisa FROM documents '
      "WHERE doc_type = 'sale_invoice'",
    );
    expect(bill.single['total_paisa'], 500000);
    expect(bill.single['paid_paisa'], 200000);
    expect(bill.single['balance_paisa'], 300000);
    final firmId = app.services.identity!.firmId;
    expect(
      (await app.services.queries.partyById(firmId, aslam))!.balance,
      const Money.rupees(3000),
    );
    expect(await app.services.database.findLedgerImbalances(), isEmpty);
  });

  testWidgets('the counter writes what a customer asked for, the list is '
      'sent, and a line leaves once the goods arrive or are ticked off', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final surf = await app.seedItem(
      name: 'Surf Excel 1kg',
      rupees: 300,
      openingStock: 0,
    );
    final agency = await _supplier(app, 'Rehman Agency');

    await tapText(tester, 'Naya Bill');
    await tester.tap(find.byTooltip('Mangwana hai mein likhein'));
    await tester.pumpAndSettle();
    await _search(tester, 'Kya maanga?', 'Surf');
    await tapText(tester, 'Surf Excel 1kg');
    await typeInto(tester, 'Kitna (marzi se) (pcs)', '3');
    await tapButton(tester, 'List mein likhein');
    expect(find.text('Surf Excel 1kg list mein likh diya'), findsOneWidget);

    await tester.tap(find.byTooltip('Mangwana hai mein likhein'));
    await tester.pumpAndSettle();
    await _search(tester, 'Kya maanga?', 'Kala namak');
    await tapButton(tester, 'List mein likhein');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapText(tester, 'Order');
    await tapText(tester, 'Mangwana hai');
    expect(find.text('Surf Excel 1kg · 3 pcs'), findsOneWidget);
    expect(find.text('Kala namak'), findsOneWidget);
    await tester.tap(find.byTooltip('List bhejein'));
    await settleReal(tester, done: () => _sheet.texts.isNotEmpty);
    expect(_sheet.texts.single, contains('mangwana hai'));
    expect(_sheet.texts.single, contains('1. Surf Excel 1kg: 3 pcs'));

    // The Surf arrives.
    await app.services.recordPurchase(
      app.services.actorNow(),
      PurchaseDraft(
        partyId: agency,
        lines: [
          PurchaseLineDraft(
            itemId: surf,
            itemName: 'Surf Excel 1kg',
            qty: Qty.units(12),
            baseQty: Qty.units(12),
            unitId: (await app.services.queries.itemById(
              app.services.identity!.firmId,
              surf,
            ))!.unitId,
            unitCode: 'pcs',
            rate: Rate.rupees(280),
          ),
        ],
      ),
    );
    // Entered from the purchase screen, the delivery would refresh every
    // list on its own; entered straight into the books, it is told to.
    ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    ).bumpRefresh();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapText(tester, 'Mangwana hai');
    expect(find.text('Surf Excel 1kg · 3 pcs'), findsNothing);
    await tapButton(tester, 'Mil gaya');
    expect(find.text('Kuch mangwana baqi nahi'), findsOneWidget);
  });

  testWidgets('what to order puts each supplier\'s items on a purchase '
      'order of their own, in one tap', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _lowAndBought(app);

    await tapText(tester, 'Order');
    await tapText(tester, 'Order banayein');
    expect(find.text('Haji Flour Mills'), findsOneWidget);
    expect(find.text('Rehman Agency'), findsOneWidget);
    await tapButton(tester, 'PO banayein (2 supplier)');

    final orders = await app.rowsOf(
      'SELECT party_name_snapshot FROM documents '
      "WHERE doc_type = 'purchase_order' ORDER BY party_name_snapshot",
    );
    expect(orders.map((o) => o['party_name_snapshot']), [
      'Haji Flour Mills',
      'Rehman Agency',
    ]);
    expect(find.text('2 PO ban gayi'), findsOneWidget);
    expect(find.text('Purchase order (PO)'), findsOneWidget);
  });

  group('at 200% on a small phone', () {
    setUpAll(_loadRealFont);

    testWidgets('an order, what to order and the shortage sheet fit', (
      tester,
    ) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(tester);
      await _lowAndBought(app);
      final firmId = app.services.identity!.firmId;
      final aslam = await app.seedParty(
        name: 'Chaudhry Muhammad Aslam Karyana Store',
      );
      final ghee = await app.services.queries.searchItems(
        firmId,
        query: 'Ghee',
      );
      await app.services.orders.place(
        OrderDraft(
          kind: OrderKind.sale,
          partyId: aslam,
          lines: [
            OrderLineDraft(
              itemId: ghee.first.id,
              itemName: ghee.first.name,
              qty: Qty.units(120),
              baseQty: Qty.units(120),
              unitId: ghee.first.unitId,
              unitCode: ghee.first.unitCode,
              rate: Rate.rupees(1250),
            ),
          ],
          dueDate: BusinessDate.now(app.services.clock).addDays(3),
        ),
      );

      await tapText(tester, 'Order');
      _expectNothingPaintsOffScreen(tester);
      await tapText(tester, 'Gahak ke order');
      await tapText(tester, 'Chaudhry Muhammad Aslam Karyana Store');
      _expectNothingPaintsOffScreen(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapText(tester, 'Order banayein');
      _expectNothingPaintsOffScreen(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapText(tester, 'Mangwana hai');
      _expectNothingPaintsOffScreen(tester);
      await tapText(tester, 'Likhein');
      _expectNothingPaintsOffScreen(tester);
    });
  });
}

/// A supplier, as the purchase screen would make one.
Future<String> _supplier(Harness app, String name) =>
    app.services.catalogue.addParty(
      app.services.actorNow(),
      PartyDraft(name: name, partyType: 'supplier'),
    );

/// Two items under their floors, each last bought from a different
/// supplier, and sold down since.
Future<void> _lowAndBought(Harness app) async {
  final services = app.services;
  final firmId = services.identity!.firmId;
  final pcs = (await services.queries.units(
    firmId,
  )).firstWhere((u) => u.code == 'pcs');
  Future<String> item(String name, int min) => services.catalogue.addItem(
    services.actorNow(),
    ItemDraft(
      name: name,
      baseUnitId: pcs.id,
      saleRate: Rate.rupees(700),
      minStock: Qty.units(min),
    ),
  );
  final atta = await item('Atta 10kg', 10);
  final ghee = await item('Ghee 1kg', 5);
  final mill = await _supplier(app, 'Haji Flour Mills');
  final agency = await _supplier(app, 'Rehman Agency');
  PurchaseLineDraft line(String id, String name, int qty) => PurchaseLineDraft(
    itemId: id,
    itemName: name,
    qty: Qty.units(qty),
    baseQty: Qty.units(qty),
    unitId: pcs.id,
    unitCode: 'pcs',
    rate: Rate.rupees(500),
  );
  await services.recordPurchase(
    services.actorNow(),
    PurchaseDraft(partyId: mill, lines: [line(atta, 'Atta 10kg', 12)]),
  );
  await services.recordPurchase(
    services.actorNow(),
    PurchaseDraft(partyId: agency, lines: [line(ghee, 'Ghee 1kg', 6)]),
  );
  final cash = (await services.queries.paymentAccounts(
    firmId,
  )).firstWhere((a) => a.modeLabel == 'cash');
  await services.postSale(
    services.actorNow(),
    SaleDraft(
      lines: [
        SaleLineDraft(
          itemId: atta,
          itemName: 'Atta 10kg',
          qty: Qty.units(10),
          baseQty: Qty.units(10),
          unitId: pcs.id,
          unitCode: 'pcs',
          rate: Rate.rupees(700),
        ),
        SaleLineDraft(
          itemId: ghee,
          itemName: 'Ghee 1kg',
          qty: Qty.units(5),
          baseQty: Qty.units(5),
          unitId: pcs.id,
          unitCode: 'pcs',
          rate: Rate.rupees(700),
        ),
      ],
      tenders: [
        TenderDraft(
          paymentAccountId: cash.id,
          mode: 'cash',
          amount: const Money.rupees(10500),
        ),
      ],
    ),
  );
}

/// Finds an item on an order's item sheet and puts it on the order.
Future<void> _addItem(
  WidgetTester tester,
  String search,
  String name, {
  required String qty,
  String? rate,
}) async {
  await tapButton(tester, 'Cheez shamil karein');
  await _search(tester, 'Talash karein', search);
  await tapText(tester, name);
  await typeInto(tester, 'Tadaad (pcs)', qty);
  if (rate != null) await typeInto(tester, 'Supplier ka rate', rate);
  await tapButton(tester, 'Order mein daalein');
}

/// Types [text] into the field labelled [label] and lets the search run.
Future<void> _search(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.widgetWithText(TextFormField, label).last, text);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

final class _FakeShareSheet extends SharePlatform {
  final texts = <String>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    if (params.text case final text?) texts.add(text);
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

/// A 360dp-wide phone with the font at 200%.
void _useASmallPhone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(720, 1600)
    ..devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

/// Every rendered piece of text still inside the screen it was drawn on.
void _expectNothingPaintsOffScreen(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  for (final element in find.byType(Text).evaluate()) {
    final box = element.renderObject! as RenderBox;
    if (!box.hasSize || box.size.isEmpty) continue;
    final left = box.localToGlobal(Offset.zero).dx;
    final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
    expect(
      right,
      lessThanOrEqualTo(width + 0.5),
      reason:
          '"${(element.widget as Text).data}" is painted from $left to '
          '$right on a $width dp screen',
    );
    expect(
      left,
      greaterThanOrEqualTo(-0.5),
      reason: '"${(element.widget as Text).data}" is painted off the left',
    );
  }
}

/// A real font, because the test font's square glyphs make every width
/// assertion pass.
Future<void> _loadRealFont() async {
  final candidates = [
    'C:/Windows/Fonts/segoeui.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
    await loader.load();
    return;
  }
  fail('no real font found to measure text with');
}
