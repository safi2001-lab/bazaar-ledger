import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// Purchase orders, sale orders, the shortage list and what to order (M41),
/// through the services the screens use, against a real database.
void main() {
  late FixedClock clock;
  late AppServices shop;
  late String firmId;
  late String cash;
  late String pcs;

  setUp(() async {
    // 3 October 2026, mid-morning in Lahore.
    clock = FixedClock(DateTime.utc(2026, 10, 3, 6));
    shop = await openInMemoryServices(clock: clock);
    await shop.setUpShop(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
    );
    firmId = (await shop.queries.currentFirm())!.id;
    cash = (await shop.queries.paymentAccounts(
      firmId,
    )).firstWhere((a) => a.modeLabel == 'cash').id;
    pcs = (await shop.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs').id;
  });

  tearDown(() => shop.close());

  Future<String> item(
    String name, {
    int rupees = 100,
    int stock = 50,
    int min = 0,
  }) => shop.catalogue.addItem(
    shop.actorNow(),
    ItemDraft(
      name: name,
      baseUnitId: pcs,
      saleRate: Rate.rupees(rupees),
      openingStock: Qty.units(stock),
      openingRate: Rate.rupees(rupees * 6 ~/ 10),
      minStock: Qty.units(min),
    ),
  );

  Future<String> party(String name, {String type = 'customer', int owed = 0}) =>
      shop.catalogue.addParty(
        shop.actorNow(),
        PartyDraft(
          name: name,
          partyType: type,
          openingBalance: Money.rupees(owed),
        ),
      );

  OrderLineDraft line(String itemId, String name, int qty, int rupees) =>
      OrderLineDraft(
        itemId: itemId,
        itemName: name,
        qty: Qty.units(qty),
        baseQty: Qty.units(qty),
        unitId: pcs,
        unitCode: 'pcs',
        rate: Rate.rupees(rupees),
      );

  PurchaseLineDraft received(String itemId, String name, int qty, int rupees) =>
      PurchaseLineDraft(
        itemId: itemId,
        itemName: name,
        qty: Qty.units(qty),
        baseQty: Qty.units(qty),
        unitId: pcs,
        unitCode: 'pcs',
        rate: Rate.rupees(rupees),
      );

  SaleLineDraft sold(String itemId, String name, int qty, int rupees) =>
      SaleLineDraft(
        itemId: itemId,
        itemName: name,
        qty: Qty.units(qty),
        baseQty: Qty.units(qty),
        unitId: pcs,
        unitCode: 'pcs',
        rate: Rate.rupees(rupees),
      );

  Future<int> count(String sql) async =>
      (await shop.database.customSelect(sql).getSingle()).data.values.first
          as int;

  Future<Money> khata(String partyId) async =>
      (await shop.queries.partyById(firmId, partyId))!.balance;

  Future<void> expectBooksBalance() async {
    expect(await shop.database.findLedgerImbalances(), isEmpty);
    expect(await shop.database.findOverAllocatedPayments(), isEmpty);
    expect((await shop.checkHealth()).findings, isEmpty);
  }

  Future<ReportTable> run(ReportKind kind) => shop.reports.run(
    kind,
    firmId: firmId,
    period: ReportPeriod.day(BusinessDate.now(clock)),
    today: BusinessDate.now(clock),
  );

  group('purchase orders', () {
    test('a purchase order posts nothing to the books', () async {
      final atta = await item('Atta 10kg');
      final mill = await party('Haji Flour Mills', type: 'supplier');
      final entries = await count('SELECT COUNT(*) FROM journal_entries');
      final moves = await count('SELECT COUNT(*) FROM stock_ledger');

      final po = await shop.orders.place(
        OrderDraft(
          kind: OrderKind.purchase,
          partyId: mill,
          lines: [line(atta, 'Atta 10kg', 20, 500)],
          dueDate: const BusinessDate('2026-10-06'),
          notes: 'Subah bhejna',
        ),
      );

      expect(po.docNo, startsWith('PO-'));
      final doc =
          (await shop.database
                  .customSelect(
                    'SELECT doc_type, status, total_paisa, paid_paisa, balance_paisa, '
                    'terms FROM documents WHERE id = ?',
                    variables: [Variable<String>(po.id)],
                  )
                  .getSingle())
              .data;
      expect(doc['doc_type'], 'purchase_order');
      expect(doc['total_paisa'], 1000000);
      expect(doc['balance_paisa'], 0);
      expect(doc['terms'], 'Expected by 2026-10-06');
      expect(await count('SELECT COUNT(*) FROM journal_entries'), entries);
      expect(await count('SELECT COUNT(*) FROM stock_ledger'), moves);
      expect(await count('SELECT COUNT(*) FROM payments'), 0);
      expect((await shop.queries.partyById(firmId, mill))!.payable, Money.zero);
      await expectBooksBalance();

      final listed = await shop.orders.list(OrderKind.purchase);
      expect(listed.single.status, OrderStatus.open);
      expect(listed.single.dueDate, const BusinessDate('2026-10-06'));
      expect(
        await shop.orders.purchaseOrderText(po.id),
        contains('Atta 10kg: 20 pcs @ Rs 500.00'),
      );
    });

    test('a delivery against a purchase order is linked to it, and what '
        'has come in follows', () async {
      final atta = await item('Atta 10kg');
      final ghee = await item('Ghee 1kg');
      final mill = await party('Haji Flour Mills', type: 'supplier');
      final po = await shop.orders.place(
        OrderDraft(
          kind: OrderKind.purchase,
          partyId: mill,
          lines: [
            line(atta, 'Atta 10kg', 10, 500),
            line(ghee, 'Ghee 1kg', 5, 300),
          ],
        ),
      );

      // Six bags arrive, at Rs 520 rather than the Rs 500 quoted.
      final first = await shop.recordPurchase(
        shop.actorNow(),
        PurchaseDraft(
          partyId: mill,
          fromOrderId: po.id,
          lines: [received(atta, 'Atta 10kg', 6, 520)],
        ),
      );
      final link =
          (await shop.database
                  .customSelect(
                    'SELECT from_document_id, link_type FROM doc_links '
                    'WHERE to_document_id = ?',
                    variables: [Variable<String>(first.documentId)],
                  )
                  .getSingle())
              .data;
      expect(link['from_document_id'], po.id);
      expect(link['link_type'], 'converted_from');

      var view = (await shop.orders.order(po.id))!;
      expect(view.row.status, OrderStatus.part);
      expect(view.lines.first.done, Qty.units(6));
      expect(view.lines.first.pendingInOrderUnit, Qty.units(4));
      expect(view.lines.last.done, Qty.zero);
      expect(view.followUps.single.docNo, first.docNo);
      expect(rateDiffers(Rate.rupees(520), view.lines.first.rate), isTrue);
      expect(
        await shop.orders.purchaseOrderText(po.id),
        allOf(contains('Atta 10kg: 4 pcs'), contains('Ghee 1kg: 5 pcs')),
      );

      await shop.recordPurchase(
        shop.actorNow(),
        PurchaseDraft(
          partyId: mill,
          fromOrderId: po.id,
          lines: [
            received(atta, 'Atta 10kg', 4, 500),
            received(ghee, 'Ghee 1kg', 5, 300),
          ],
        ),
      );
      view = (await shop.orders.order(po.id))!;
      expect(view.row.status, OrderStatus.done);
      expect(view.pendingValue, Money.zero);
      expect(
        await shop.orders.list(OrderKind.purchase, standingOnly: true),
        isEmpty,
      );
      await expectBooksBalance();
    });

    test('a delivery from another supplier, or against a cancelled order, '
        'is refused and nothing is written', () async {
      final atta = await item('Atta 10kg');
      final mill = await party('Haji Flour Mills', type: 'supplier');
      final other = await party('Bismillah Traders', type: 'supplier');
      final po = await shop.orders.place(
        OrderDraft(
          kind: OrderKind.purchase,
          partyId: mill,
          lines: [line(atta, 'Atta 10kg', 10, 500)],
        ),
      );
      final bills = await count(
        "SELECT COUNT(*) FROM documents WHERE doc_type = 'purchase_bill'",
      );

      await expectLater(
        shop.recordPurchase(
          shop.actorNow(),
          PurchaseDraft(
            partyId: other,
            fromOrderId: po.id,
            lines: [received(atta, 'Atta 10kg', 10, 500)],
          ),
        ),
        throwsA(isA<OrderRefused>()),
      );
      await shop.orders.cancel(po.id, reason: 'Rate zyada bataya');
      await expectLater(
        shop.recordPurchase(
          shop.actorNow(),
          PurchaseDraft(
            partyId: mill,
            fromOrderId: po.id,
            lines: [received(atta, 'Atta 10kg', 10, 500)],
          ),
        ),
        throwsA(isA<OrderRefused>()),
      );
      expect(
        await count(
          "SELECT COUNT(*) FROM documents WHERE doc_type = 'purchase_bill'",
        ),
        bills,
      );
      expect(
        (await shop.orders.order(po.id))!.row.status,
        OrderStatus.cancelled,
      );
    });

    test('an order cancelled after part of it came is closed, and what came '
        'stands', () async {
      final atta = await item('Atta 10kg');
      final mill = await party('Haji Flour Mills', type: 'supplier');
      final po = await shop.orders.place(
        OrderDraft(
          kind: OrderKind.purchase,
          partyId: mill,
          lines: [line(atta, 'Atta 10kg', 10, 500)],
        ),
      );
      await shop.recordPurchase(
        shop.actorNow(),
        PurchaseDraft(
          partyId: mill,
          fromOrderId: po.id,
          lines: [received(atta, 'Atta 10kg', 3, 500)],
        ),
      );
      await expectLater(
        shop.orders.cancel(po.id, reason: '  '),
        throwsA(isA<OrderRefused>()),
      );
      await shop.orders.cancel(po.id, reason: 'Baqi ki zaroorat nahi');
      final view = (await shop.orders.order(po.id))!;
      expect(view.row.status, OrderStatus.closed);
      expect(view.lines.single.done, Qty.units(3));
      expect((await run(ReportKind.openPurchaseOrders)).summary.first.count, 0);
    });
  });

  group('sale orders', () {
    Future<({String id, String docNo})> order(String customer, String ghee) =>
        shop.orders.place(
          OrderDraft(
            kind: OrderKind.sale,
            partyId: customer,
            lines: [line(ghee, 'Ghee 1kg', 10, 500)],
            dueDate: const BusinessDate('2026-10-09'),
          ),
        );

    Future<PostedSale> billFrom(
      String orderId,
      String customer,
      String ghee, {
      int qty = 10,
    }) => shop.postSale(
      shop.actorNow(),
      SaleDraft(
        lines: [sold(ghee, 'Ghee 1kg', qty, 500)],
        partyId: customer,
        partyName: 'Aslam Store',
        convertedFromId: orderId,
      ),
    );

    test('a sale order is billed from, and the advance paid on it settles '
        'the bill', () async {
      final ghee = await item('Ghee 1kg');
      final aslam = await party('Aslam Store');
      final so = await order(aslam, ghee);
      expect(so.docNo, startsWith('SO-'));

      await shop.orders.takeAdvance(
        so.id,
        amount: const Money.rupees(2000),
        paymentAccountId: cash,
        mode: 'cash',
      );
      expect(await khata(aslam), const Money.rupees(-2000));
      expect(
        (await shop.orders.list(OrderKind.sale)).single.advance,
        const Money.rupees(2000),
      );

      final bill = await billFrom(so.id, aslam, ghee);
      expect(bill.total, const Money.rupees(5000));
      expect(bill.paid, const Money.rupees(2000));
      expect(bill.balance, const Money.rupees(3000));
      expect(await khata(aslam), const Money.rupees(3000));
      final open = await shop.queries.openBillsFor(firmId, aslam);
      expect(open.single.outstanding, const Money.rupees(3000));

      final view = (await shop.orders.order(so.id))!;
      expect(view.row.status, OrderStatus.done);
      expect(view.followUps.single.docNo, bill.docNo);
      await expectBooksBalance();
    });

    test(
      'a bill paid in full at the counter leaves the advance held',
      () async {
        final ghee = await item('Ghee 1kg');
        final aslam = await party('Aslam Store');
        final so = await order(aslam, ghee);
        await shop.orders.takeAdvance(
          so.id,
          amount: const Money.rupees(1000),
          paymentAccountId: cash,
          mode: 'cash',
        );
        final bill = await shop.postSale(
          shop.actorNow(),
          SaleDraft(
            lines: [sold(ghee, 'Ghee 1kg', 10, 500)],
            partyId: aslam,
            partyName: 'Aslam Store',
            convertedFromId: so.id,
            tenders: [
              TenderDraft(
                paymentAccountId: cash,
                mode: 'cash',
                amount: const Money.rupees(5000),
              ),
            ],
          ),
        );
        expect(bill.balance, Money.zero);
        expect(await khata(aslam), const Money.rupees(-1000));
        await expectBooksBalance();
      },
    );

    test(
      'an advance is held for the order, not swallowed by old udhaar',
      () async {
        final ghee = await item('Ghee 1kg');
        final aslam = await party('Aslam Store', owed: 1000);
        final so = await order(aslam, ghee);
        await shop.orders.takeAdvance(
          so.id,
          amount: const Money.rupees(500),
          paymentAccountId: cash,
          mode: 'cash',
        );
        expect(await khata(aslam), const Money.rupees(500));

        final bill = await billFrom(so.id, aslam, ghee, qty: 4);
        expect(bill.paid, const Money.rupees(500));
        expect(bill.balance, const Money.rupees(1500));
        expect(await khata(aslam), const Money.rupees(2500));

        // The rest of the order, a second bill: nothing left to take.
        final view = (await shop.orders.order(so.id))!;
        expect(view.row.status, OrderStatus.part);
        expect(view.lines.single.pendingInOrderUnit, Qty.units(6));
        final second = await billFrom(so.id, aslam, ghee, qty: 6);
        expect(second.paid, Money.zero);
        expect((await shop.orders.order(so.id))!.row.status, OrderStatus.done);
        expect(await khata(aslam), const Money.rupees(5500));
        await expectBooksBalance();
      },
    );

    test('cancelling the bill made from a sale order holds the advance '
        'again, and the order is open again', () async {
      final ghee = await item('Ghee 1kg');
      final aslam = await party('Aslam Store');
      final so = await order(aslam, ghee);
      await shop.orders.takeAdvance(
        so.id,
        amount: const Money.rupees(2000),
        paymentAccountId: cash,
        mode: 'cash',
      );
      final bill = await billFrom(so.id, aslam, ghee);
      await shop.voidDocument(
        shop.actorNow(),
        documentId: bill.documentId,
        reason: 'Galat bill',
      );
      expect(await khata(aslam), const Money.rupees(-2000));
      expect((await shop.orders.order(so.id))!.row.status, OrderStatus.open);

      // Billed again, the advance is taken again.
      final again = await billFrom(so.id, aslam, ghee);
      expect(again.paid, const Money.rupees(2000));
      expect(await khata(aslam), const Money.rupees(3000));
      await expectBooksBalance();
    });

    test('cancelling the advance receipt after the bill leaves the bill '
        'owed in full on the khata', () async {
      final ghee = await item('Ghee 1kg');
      final aslam = await party('Aslam Store');
      final so = await order(aslam, ghee);
      final advance = await shop.orders.takeAdvance(
        so.id,
        amount: const Money.rupees(2000),
        paymentAccountId: cash,
        mode: 'cash',
      );
      await billFrom(so.id, aslam, ghee);
      await shop.corrections.cancelPayment(
        shop.actorNow(),
        paymentId: advance.paymentId,
        reason: 'Paisay wapas kar diye',
      );
      expect(await khata(aslam), const Money.rupees(5000));
      await expectBooksBalance();
    });

    test('a sale order goes out on a challan, and the bill made from the '
        'challan takes its advance', () async {
      final ghee = await item('Ghee 1kg');
      final aslam = await party('Aslam Store');
      final so = await order(aslam, ghee);
      await shop.orders.takeAdvance(
        so.id,
        amount: const Money.rupees(1000),
        paymentAccountId: cash,
        mode: 'cash',
      );
      final challan = await shop.issueChallan(
        shop.actorNow(),
        SaleDraft(
          lines: [sold(ghee, 'Ghee 1kg', 10, 500)],
          partyId: aslam,
          partyName: 'Aslam Store',
          convertedFromId: so.id,
        ),
      );
      expect((await shop.orders.order(so.id))!.row.status, OrderStatus.done);

      final bill = await shop.postSale(
        shop.actorNow(),
        SaleDraft(
          lines: [sold(ghee, 'Ghee 1kg', 10, 500)],
          partyId: aslam,
          partyName: 'Aslam Store',
          convertedFromId: challan.id,
        ),
      );
      expect(bill.paid, const Money.rupees(1000));
      expect(await khata(aslam), const Money.rupees(4000));
      await expectBooksBalance();
    });
  });

  group('the shortage list', () {
    test('a line noted at the counter is listed, sent, and leaves once a '
        'delivery of it arrives', () async {
      final surf = await item('Surf Excel 1kg', stock: 0);
      final mill = await party('Unilever Distributor', type: 'supplier');
      await shop.orders.noteShortage(
        ShortageDraft(name: 'Surf', itemId: surf, qty: Qty.units(3)),
      );
      await shop.orders.noteShortage(
        const ShortageDraft(name: 'Kala namak', note: 'Bibi ne poocha'),
      );
      final list = await shop.orders.shortage();
      expect(list.map((e) => e.name), ['Surf Excel 1kg', 'Kala namak']);
      expect(list.first.addedBy, 'Malik Sahib');
      expect(
        await shop.orders.shortageText(),
        allOf(
          contains('Chishti Kiryana Store: mangwana hai'),
          contains('1. Surf Excel 1kg: 3'),
          contains('2. Kala namak (Bibi ne poocha)'),
        ),
      );

      clock.advance(const Duration(minutes: 5));
      await shop.recordPurchase(
        shop.actorNow(),
        PurchaseDraft(
          partyId: mill,
          lines: [received(surf, 'Surf Excel 1kg', 12, 280)],
        ),
      );
      expect((await shop.orders.shortage()).map((e) => e.name), ['Kala namak']);

      await shop.orders.clearShortage([
        (await shop.orders.shortage()).single.id,
      ]);
      expect(await shop.orders.shortage(), isEmpty);
      await expectLater(
        shop.orders.noteShortage(const ShortageDraft(name: '  ')),
        throwsA(isA<OrderRefused>()),
      );
    });
  });

  group('what to order', () {
    test('suggestions come from the low stock list less what is on order, '
        'with the counter\'s asks, grouped by the supplier each last came '
        'from, and become one purchase order each', () async {
      final atta = await item('Atta 10kg', stock: 0, min: 10);
      final ghee = await item('Ghee 1kg', stock: 0, min: 5);
      final dal = await item('Dal Chana', stock: 2, min: 10);
      final surf = await item('Surf Excel 1kg', stock: 20);
      final mill = await party('Haji Flour Mills', type: 'supplier');
      final agency = await party('Rehman Agency', type: 'supplier');

      // Deliveries say who each came from; then it sells down.
      await shop.recordPurchase(
        shop.actorNow(),
        PurchaseDraft(
          partyId: mill,
          lines: [
            received(atta, 'Atta 10kg', 30, 500),
            received(dal, 'Dal Chana', 4, 250),
          ],
        ),
      );
      await shop.recordPurchase(
        shop.actorNow(),
        PurchaseDraft(
          partyId: agency,
          lines: [
            received(ghee, 'Ghee 1kg', 6, 300),
            received(surf, 'Surf Excel 1kg', 5, 280),
          ],
        ),
      );
      await shop.postSale(
        shop.actorNow(),
        SaleDraft(
          lines: [
            sold(atta, 'Atta 10kg', 26, 600),
            sold(ghee, 'Ghee 1kg', 5, 400),
            sold(dal, 'Dal Chana', 2, 300),
          ],
          tenders: [
            TenderDraft(
              paymentAccountId: cash,
              mode: 'cash',
              amount: const Money.rupees(18200),
            ),
          ],
        ),
      );
      // A customer asked for six Surf; the shelf has plenty, but the
      // counter's ask is on the list.
      await shop.orders.noteShortage(
        ShortageDraft(name: 'Surf', itemId: surf, qty: Qty.units(6)),
      );
      // Ten Dal already on its way.
      await shop.orders.place(
        OrderDraft(
          kind: OrderKind.purchase,
          partyId: mill,
          lines: [line(dal, 'Dal Chana', 10, 250)],
        ),
      );

      final groups = await shop.orders.reorder();
      expect(groups.map((g) => g.supplierName), [
        'Haji Flour Mills',
        'Rehman Agency',
      ]);
      final fromMill = groups.first.lines;
      // Atta: 26 sold in 30 days is 13 for a fortnight, less 4 on the
      // shelf, and at least back to 10: 9. Dal is covered by its order.
      expect(fromMill.map((l) => l.itemName), ['Atta 10kg']);
      expect(fromMill.single.qty, Qty.units(9));
      expect(fromMill.single.rate, Rate.rupees(500));
      final fromAgency = {for (final l in groups.last.lines) l.itemName: l};
      // Ghee: one left of a floor of five, and two and a half a fortnight
      // selling: back up to the floor, 4.
      expect(fromAgency['Ghee 1kg']!.qty, Qty.units(4));
      expect(fromAgency['Surf Excel 1kg']!.qty, Qty.units(6));
      expect(fromAgency['Surf Excel 1kg']!.wasAsked, isTrue);

      final placed = await shop.orders.placeAll([
        for (final g in groups)
          OrderDraft(
            kind: OrderKind.purchase,
            partyId: g.supplierId!,
            lines: [for (final l in g.lines) l.toOrderLine()],
          ),
      ]);
      expect(placed, hasLength(2));
      expect(await shop.orders.reorder(), isEmpty);
      expect(
        (await shop.orders.list(OrderKind.purchase, standingOnly: true)).length,
        3,
      );
    });

    test('an item never bought from anybody waits for a supplier to be '
        'picked', () async {
      final soap = await item('Lux Soap', stock: 1, min: 6);
      final groups = await shop.orders.reorder();
      expect(groups.single.supplierId, isNull);
      expect(groups.single.lines.single.itemId, soap);
      expect(groups.single.lines.single.qty, Qty.units(5));
    });
  });

  group('order reports', () {
    test('open purchase orders, open sale orders and the items on both, '
        'with what has come and what is still to', () async {
      final atta = await item('Atta 10kg');
      final ghee = await item('Ghee 1kg');
      final mill = await party('Haji Flour Mills', type: 'supplier');
      final aslam = await party('Aslam Store');
      final po = await shop.orders.place(
        OrderDraft(
          kind: OrderKind.purchase,
          partyId: mill,
          lines: [line(atta, 'Atta 10kg', 10, 500)],
          dueDate: const BusinessDate('2026-10-03'),
        ),
      );
      await shop.recordPurchase(
        shop.actorNow(),
        PurchaseDraft(
          partyId: mill,
          fromOrderId: po.id,
          lines: [received(atta, 'Atta 10kg', 4, 500)],
        ),
      );
      final so = await shop.orders.place(
        OrderDraft(
          kind: OrderKind.sale,
          partyId: aslam,
          lines: [line(ghee, 'Ghee 1kg', 8, 450)],
        ),
      );
      await shop.orders.takeAdvance(
        so.id,
        amount: const Money.rupees(1000),
        paymentAccountId: cash,
        mode: 'cash',
      );

      final pos = await run(ReportKind.openPurchaseOrders);
      final poRow = pos.rows.first.cells;
      expect(poRow[2], 'Haji Flour Mills');
      expect(poRow[4], const Money.rupees(5000));
      expect(poRow[5], const Money.rupees(2000), reason: 'received');
      expect(poRow[6], const Money.rupees(3000), reason: 'still to come');
      expect(poRow.last, 'Part received');
      expect(ReportEngine.isAsOfToday(ReportKind.openPurchaseOrders), isTrue);

      final sos = await run(ReportKind.openSaleOrders);
      expect(sos.rows.first.cells[2], 'Aslam Store');
      expect(sos.rows.first.cells[7], const Money.rupees(1000));
      expect(sos.rows.first.cells.last, 'Open');

      final items = await run(ReportKind.orderItemsDue);
      final byName = {for (final r in items.rows) r.cells.first: r.cells};
      expect(byName['Atta 10kg']![2], Qty.units(10));
      expect(byName['Atta 10kg']![3], Qty.units(4));
      expect(byName['Atta 10kg']![4], Qty.units(6));
      expect(byName['Ghee 1kg']![1], 'Sale orders');
      expect(byName['Ghee 1kg']![6], const Money.rupees(3600));
    });
  });
}
