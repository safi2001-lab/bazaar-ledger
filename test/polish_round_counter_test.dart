import 'package:bazaar_ledger/design/components.dart';
import 'package:bazaar_ledger/features/pos/cart.dart';
import 'package:bazaar_ledger/features/pos/cart_draft.dart';
import 'package:bazaar_ledger/features/pos/pos_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// The polish round at the counter (M54): the small things the milestones
/// that built the counter said they had left.
///
/// Each through the screens a shopkeeper uses, on a real database, and read
/// back out of the books.
void main() {
  group('a customer\'s order at the counter', () {
    testWidgets('goes out on a challan from the payment sheet, and the bill '
        'made from the challan takes its advance', (tester) async {
      final app = await Harness.startWithShop(tester);
      final shop = await _orderWithAdvance(
        app,
        owed: 0,
        qty: 10,
        advance: 2000,
      );

      await _orderToCounter(tester);
      await tapButton(tester, 'Paisay lein');
      // Only the challan: a quotation of an order is not a thing, and rate
      // later is goods with no price, which an order already has.
      expect(find.text('Quotation banayein'), findsNothing);
      await tapButton(tester, 'Challan banayein');

      final challan = await app.rowsOf(
        'SELECT d.id, d.total_paisa, l.from_document_id FROM documents d '
        'JOIN doc_links l ON l.to_document_id = d.id '
        "WHERE d.doc_type = 'delivery_challan'",
      );
      expect(challan.single['from_document_id'], shop.orderId);
      expect(challan.single['total_paisa'], 500000);
      expect(
        (await app.services.orders.order(shop.orderId))!.row.status,
        OrderStatus.done,
      );
      // The goods left with the challan; nothing is owed yet.
      expect(await _khata(app, shop.partyId), const Money.rupees(-2000));

      final bill = await app.services.postSale(
        app.services.actorNow(),
        SaleDraft(
          lines: [shop.line(10)],
          partyId: shop.partyId,
          partyName: 'Aslam Store',
          convertedFromId: challan.single['id']! as String,
        ),
      );
      expect(bill.paid, const Money.rupees(2000));
      expect(bill.balance, const Money.rupees(3000));
      expect(await _khata(app, shop.partyId), const Money.rupees(3000));
      expect(await app.services.database.findLedgerImbalances(), isEmpty);
    });

    testWidgets('a customer at their credit limit is billed what their '
        "order's advance covers, and asked about anything past it", (
      tester,
    ) async {
      final app = await Harness.startWithShop(tester);
      // Rs 7,000 of old udhaar on a Rs 5,000 limit, and Rs 2,000 paid down
      // on a Rs 2,000 order: the khata reads Rs 5,000, right at the limit.
      final shop = await _orderWithAdvance(
        app,
        owed: 7000,
        limit: 5000,
        qty: 4,
        advance: 2000,
      );
      expect(await _khata(app, shop.partyId), const Money.rupees(5000));

      await _orderToCounter(tester);
      await _onUdhaarAndSave(tester);

      expect(find.text('Udhaar ki hadd se ziyada'), findsNothing);
      final bill = await app.rowsOf(
        'SELECT total_paisa, paid_paisa, balance_paisa FROM documents '
        "WHERE doc_type = 'sale_invoice'",
      );
      expect(bill.single['total_paisa'], 200000);
      expect(bill.single['paid_paisa'], 200000);
      expect(bill.single['balance_paisa'], 0);

      // A second order, Rs 3,000 with Rs 1,000 down: Rs 2,000 of it would
      // be new udhaar, and that is asked about, landing where it always
      // said — the khata with the advance spent, plus the bill.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await _placeOrder(app, shop, qty: 6, advance: 1000);
      expect(await _khata(app, shop.partyId), const Money.rupees(6000));
      // Newest first: the order just placed.
      await _orderToCounter(tester);
      await _onUdhaarAndSave(tester);

      expect(find.text('Udhaar ki hadd se ziyada'), findsOneWidget);
      expect(find.textContaining('9,000.00'), findsWidgets);
      expect(
        await app.rowsOf(
          "SELECT id FROM documents WHERE doc_type = 'sale_invoice'",
        ),
        hasLength(1),
      );
    });
  });

  group('a bill rung again with a bonus on it', () {
    testWidgets('brings its free soap back under the line, and does not '
        'call it left out', (tester) async {
      final app = await Harness.startWithShop(tester);
      final old = await _soldWithBonus(
        app,
        schemeSince: BonusRule(buy: Qty.units(10), free: Qty.one),
      );

      await _billAgain(tester, old);

      expect(find.text('$old ki naqal counter par hai'), findsOneWidget);
      expect(find.textContaining('Yeh nahi aayin'), findsNothing);
      expect(find.text('Bonus / muft: Lux Soap 1 pcs'), findsOneWidget);
    });

    testWidgets('names the free line when the scheme gives it no longer', (
      tester,
    ) async {
      final app = await Harness.startWithShop(tester);
      final old = await _soldWithBonus(app);

      await _billAgain(tester, old);

      expect(find.text('Yeh nahi aayin: Lux Soap (muft)'), findsOneWidget);
      expect(find.textContaining('Bonus / muft'), findsNothing);
    });
  });

  testWidgets('a challan billed after its scheme changed is billed as it was '
      'sent, its free soap and all', (tester) async {
    final app = await Harness.startWithShop(tester);
    final services = app.services;
    final firmId = services.identity!.firmId;
    final soapId = await app.seedItem(name: 'Lux Soap', rupees: 100);
    final soap = (await services.queries.itemById(firmId, soapId))!;
    final rashid = await app.seedParty(name: 'Rashid Traders');
    SaleLineDraft line(int qty, {bool free = false}) => SaleLineDraft(
      itemId: soapId,
      itemName: soap.name,
      qty: Qty.units(qty),
      baseQty: Qty.units(qty),
      unitId: soap.unitId,
      unitCode: soap.unitCode,
      rate: free ? Rate.zero : Rate.rupees(100),
      isFreeItem: free,
    );
    // Sent on Monday on a 10+1 scheme, the free one with the goods.
    await services.saveItemScheme(
      ItemScheme(
        itemId: soapId,
        bonus: BonusRule(buy: Qty.units(10), free: Qty.one),
      ),
    );
    await services.issueChallan(
      services.actorNow(),
      SaleDraft(
        lines: [line(10), line(1, free: true)],
        partyId: rashid,
        partyName: 'Rashid Traders',
      ),
    );
    // By Saturday the distributor's scheme is 12+1.
    await services.saveItemScheme(
      ItemScheme(
        itemId: soapId,
        bonus: BonusRule(buy: Qty.units(12), free: Qty.one),
      ),
    );

    await tester.pumpAndSettle();
    await tapText(tester, 'Challan');
    await tapText(tester, 'Rashid Traders');
    await tapButton(tester, 'Is se bill banayein');
    expect(
      find.text('Bonus / muft (challan par gaya): Lux Soap 1 pcs'),
      findsOneWidget,
    );
    expect(find.text('Scheme 12+1'), findsNothing);
    await tapButton(tester, 'Paisay lein');
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();
    await tapButton(tester, 'Save karein');

    final lines = await app.rowsOf(
      'SELECT dl.is_free_item f, dl.base_qty_thousandths b, '
      'dl.line_total_paisa t FROM document_lines dl '
      'JOIN documents d ON d.id = dl.document_id '
      "WHERE d.doc_type = 'sale_invoice' ORDER BY dl.line_no",
    );
    expect(lines, [
      {'f': 0, 'b': 10000, 't': 100000},
      {'f': 1, 'b': 1000, 't': 0},
    ]);
    expect(
      await app.scalar<int>(
        "SELECT total_paisa FROM documents WHERE doc_type = 'sale_invoice'",
      ),
      100000,
    );
    expect(await services.database.findLedgerImbalances(), isEmpty);
  });

  group('the counter counts in packs', () {
    testWidgets('the stock warning says the shelf and the bill in cartons', (
      tester,
    ) async {
      final app = await Harness.startWithShop(tester);
      await _gala(app, onHand: 53);

      await _openCounter(tester);
      await _ring(tester, 'Gala');
      await _setQty(tester, 'Tadaad (pcs)', '60');

      expect(
        find.text('Stock sirf 2 ctn + 5 pcs hai — phir bhi bechein?'),
        findsOneWidget,
      );
      expect(
        find.text('Gala Biscuit: bill par 2 ctn + 12 pcs'),
        findsOneWidget,
      );
      await tester.tap(find.text('Haan, bechein'));
      await tester.pumpAndSettle();
      expect(_cart(tester).lines.single.qty, Qty.units(60));
    });

    testWidgets('a line rung by the dozen still reads in dozens once a piece '
        'is added, and the bill takes the pieces exactly', (tester) async {
      final app = await Harness.startWithShop(tester);
      // Sold loose and by the dozen, with no carton of its own.
      await _gala(app, carton: false);

      await _openCounter(tester);
      await _ring(tester, 'Gala');
      await _openLine(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'dozen'));
      await tester.pumpAndSettle();
      await _setQty(tester, 'Tadaad (dozen)', '3');
      expect(find.text('3 doz'), findsOneWidget);

      await _setQty(tester, 'Tadaad (dozen)', '3 doz 4');
      final line = _cart(tester).lines.single;
      expect(line.sellingUnitCode, 'pcs', reason: 'never 3.333 dozen');
      expect(line.qty, Qty.units(40));
      expect(line.rate, Rate.rupees(40));
      expect(find.text('3 doz + 4 pcs'), findsOneWidget);

      // One more piece from the line's own stepper: still in dozens.
      await _clearSearch(tester);
      await tester.tap(find.byIcon(Icons.add).last);
      await tester.pumpAndSettle();
      expect(_cart(tester).lines.single.qty, Qty.units(41));
      expect(find.text('3 doz + 5 pcs'), findsOneWidget);

      // A cashier who comes back to a killed app finds it as it was, and a
      // draft written before M54 still opens.
      final cart = _cart(tester);
      final back = CartDraft.decode(CartDraft.encode(cart))!;
      expect(back.lines.single.countedInUnitId, line.countedInUnitId);
      expect(back.lines.single.qty, Qty.units(41));
      final v5 = CartDraft.decode(
        CartDraft.encode(cart).replaceFirst('"v":6', '"v":5'),
      )!;
      expect(v5.lines.single.qty, Qty.units(41));

      await tapButton(tester, 'Paisay lein');
      await typeInto(tester, 'Diye gaye', '1640');
      await tapButton(tester, 'Save karein');
      await tester.pumpAndSettle();
      final rows = await app.rowsOf(
        'SELECT unit_code_snapshot u, qty_thousandths q, gross_paisa g '
        'FROM document_lines',
      );
      expect(rows.single, {'u': 'pcs', 'q': 41000, 'g': 164000});
    });
  });
}

Future<String> _gala(
  Harness app, {
  int onHand = 100,
  bool carton = true,
}) async {
  final units = await app.services.queries.units(app.services.identity!.firmId);
  String unit(String code) => units.firstWhere((u) => u.code == code).id;
  return app.services.catalogue.addItem(
    app.services.actorNow(),
    ItemDraft(
      name: 'Gala Biscuit',
      baseUnitId: unit('pcs'),
      saleRate: Rate.rupees(40),
      openingStock: Qty.units(onHand),
      openingRate: Rate.rupees(30),
      packs: [
        if (carton) ItemPack(unitId: unit('carton'), size: Qty.units(24)),
      ],
    ),
  );
}

Cart _cart(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(PosScreen)),
).read(cartProvider);

Future<void> _openCounter(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Naya Bill').first);
  await tester.pumpAndSettle();
}

Future<void> _ring(WidgetTester tester, String query) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Talash karein').first,
    query,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.add_circle_outline).first);
  await tester.pumpAndSettle();
}

Future<void> _clearSearch(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Talash karein').first,
    '',
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// Taps the quantity of the first line, which opens its editor.
Future<void> _openLine(WidgetTester tester) async {
  await _clearSearch(tester);
  await tester.tap(
    find.ancestor(of: find.byType(BlQty), matching: find.byType(InkWell)).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _setQty(WidgetTester tester, String label, String qty) async {
  await _openLine(tester);
  await typeInto(tester, label, qty);
  await tapButton(tester, 'Ho gaya');
  await tester.pumpAndSettle();
}

/// Ten soaps sold on a 10+1 scheme, the free one on the bill; with
/// [schemeSince], the scheme as it stands when the bill is rung again. The
/// bill's number.
Future<String> _soldWithBonus(Harness app, {BonusRule? schemeSince}) async {
  final services = app.services;
  final firmId = services.identity!.firmId;
  final soapId = await app.seedItem(name: 'Lux Soap', rupees: 100);
  final soap = (await services.queries.itemById(firmId, soapId))!;
  await services.saveItemScheme(
    ItemScheme(
      itemId: soapId,
      bonus: BonusRule(buy: Qty.units(10), free: Qty.one),
    ),
  );
  SaleLineDraft line(int qty, {bool free = false}) => SaleLineDraft(
    itemId: soapId,
    itemName: soap.name,
    qty: Qty.units(qty),
    baseQty: Qty.units(qty),
    unitId: soap.unitId,
    unitCode: soap.unitCode,
    rate: free ? Rate.zero : Rate.rupees(100),
    isFreeItem: free,
  );
  final cash = (await services.queries.paymentAccounts(
    firmId,
  )).firstWhere((a) => a.modeLabel == 'cash');
  final bill = await services.postSale(
    services.actorNow(),
    SaleDraft(
      lines: [line(10), line(1, free: true)],
      tenders: [
        TenderDraft(
          paymentAccountId: cash.id,
          mode: 'cash',
          amount: const Money.rupees(1000),
        ),
      ],
    ),
  );
  await services.saveItemScheme(ItemScheme(itemId: soapId, bonus: schemeSince));
  return bill.docNo;
}

/// "Isi tarah ka naya bill" on [docNo], at today's prices.
Future<void> _billAgain(WidgetTester tester, String docNo) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Farokht');
  await tester.tap(find.text(docNo).first);
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Aur'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Isi tarah ka naya bill').last);
  await tester.pumpAndSettle();
  await tapButton(tester, 'Aaj ke rate');
}

/// A customer, Ghee at Rs 500, and a sale order of [qty] with [advance]
/// paid down on it in cash.
Future<_Shop> _orderWithAdvance(
  Harness app, {
  required int owed,
  int? limit,
  required int qty,
  required int advance,
}) async {
  final services = app.services;
  final firmId = services.identity!.firmId;
  final ghee = await app.seedItem(name: 'Ghee 1kg', rupees: 500);
  final aslam = await services.catalogue.addParty(
    services.actorNow(),
    PartyDraft(
      name: 'Aslam Store',
      partyType: 'customer',
      openingBalance: Money.rupees(owed),
      creditLimit: limit == null ? null : Money.rupees(limit),
    ),
  );
  final item = (await services.queries.itemById(firmId, ghee))!;
  final cash = (await services.queries.paymentAccounts(
    firmId,
  )).firstWhere((a) => a.modeLabel == 'cash');
  final shop = _Shop(app, aslam, item, cash.id);
  shop.orderId = (await services.orders.place(
    OrderDraft(
      kind: OrderKind.sale,
      partyId: aslam,
      lines: [shop.orderLine(qty)],
    ),
  )).id;
  await services.orders.takeAdvance(
    shop.orderId,
    amount: Money.rupees(advance),
    paymentAccountId: cash.id,
    mode: 'cash',
  );
  return shop;
}

/// Another order for [shop]'s customer, with [advance] down.
Future<void> _placeOrder(
  Harness app,
  _Shop shop, {
  required int qty,
  required int advance,
}) async {
  final placed = await app.services.orders.place(
    OrderDraft(
      kind: OrderKind.sale,
      partyId: shop.partyId,
      lines: [shop.orderLine(qty)],
    ),
  );
  await app.services.orders.takeAdvance(
    placed.id,
    amount: Money.rupees(advance),
    paymentAccountId: shop.cashId,
    mode: 'cash',
  );
}

/// Opens the customer's newest order and puts it on the counter.
Future<void> _orderToCounter(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Order');
  await tapText(tester, 'Gahak ke order');
  await tapText(tester, 'Aslam Store');
  await tapButton(tester, 'Counter par bill banayein');
}

Future<void> _onUdhaarAndSave(WidgetTester tester) async {
  await tapButton(tester, 'Paisay lein');
  await tester.tap(find.byType(SwitchListTile).first);
  await tester.pumpAndSettle();
  await tapButton(tester, 'Save karein');
}

Future<Money> _khata(Harness app, String partyId) async =>
    (await app.services.queries.partyById(
      app.services.identity!.firmId,
      partyId,
    ))!.balance;

final class _Shop {
  _Shop(this.app, this.partyId, this.ghee, this.cashId);

  final Harness app;
  final String partyId;
  final ItemSummary ghee;
  final String cashId;
  late String orderId;

  OrderLineDraft orderLine(int qty) => OrderLineDraft(
    itemId: ghee.id,
    itemName: ghee.name,
    qty: Qty.units(qty),
    baseQty: Qty.units(qty),
    unitId: ghee.unitId,
    unitCode: ghee.unitCode,
    rate: Rate.rupees(500),
  );

  SaleLineDraft line(int qty) => SaleLineDraft(
    itemId: ghee.id,
    itemName: ghee.name,
    qty: Qty.units(qty),
    baseQty: Qty.units(qty),
    unitId: ghee.unitId,
    unitCode: ghee.unitCode,
    rate: Rate.rupees(500),
  );
}
