import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// Bonus and slabs the way the trade runs (M43), against a real database:
/// what the shop's schemes put on a bill, what the books make of it, who
/// may change them, and what a delivery's own "10+1" does to the cost.
void main() {
  late AppServices shop;
  late String firmId;
  late String ownerId;
  late String pcs;
  late String carton;
  late String cash;
  late String soap;
  late String shampoo;
  late String oil;

  setUp(() async {
    shop = await openInMemoryServices();
    await shop.setUpShop(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
    );
    firmId = (await shop.queries.currentFirm())!.id;
    ownerId = shop.currentUser!.id;
    final units = await shop.queries.units(firmId);
    pcs = units.firstWhere((u) => u.code == 'pcs').id;
    carton = units.firstWhere((u) => u.code == 'carton').id;
    cash = (await shop.queries.paymentAccounts(
      firmId,
    )).firstWhere((a) => a.modeLabel == 'cash').id;
    Future<String> item(String name, int rupees, int cost, {int stock = 100}) =>
        shop.catalogue.addItem(
          shop.actorNow(),
          ItemDraft(
            name: name,
            baseUnitId: pcs,
            saleRate: Rate.rupees(rupees),
            openingStock: Qty.units(stock),
            openingRate: Rate.rupees(cost),
          ),
        );
    soap = await item('Lux Soap', 100, 60);
    shampoo = await item('Sunsilk Shampoo', 400, 300);
    oil = await item('Dalda Oil 1L', 50, 40, stock: 240);
    await shop.catalogue.updateItem(
      shop.actorNow(),
      oil,
      ItemDraft(
        name: 'Dalda Oil 1L',
        baseUnitId: pcs,
        saleRate: Rate.rupees(50),
        packs: [ItemPack(unitId: carton, size: Qty.units(24))],
      ),
    );
  });

  tearDown(() => shop.close());

  SaleLineDraft line(String itemId, String name, int qty, int rupees) =>
      SaleLineDraft(
        itemId: itemId,
        itemName: name,
        qty: Qty.units(qty),
        baseQty: Qty.units(qty),
        unitId: pcs,
        unitCode: 'pcs',
        rate: Rate.rupees(rupees),
      );

  /// [paid] with the bonus the shop's schemes give, as the counter adds it.
  Future<List<SaleLineDraft>> withBonus(List<SaleLineDraft> paid) async {
    final book = await shop.schemeBook();
    return [
      ...paid,
      for (final g in book.bonusFor(SchemeBook.paidBaseOf(paid))) g.toLine(),
    ];
  }

  Future<PostedSale> sell(
    List<SaleLineDraft> lines, {
    Money billDiscount = Money.zero,
    String? partyId,
    bool onUdhaar = false,
  }) async {
    final draft = SaleDraft(
      lines: lines,
      partyId: partyId,
      billDiscount: billDiscount,
      roundToRupee: false,
    );
    final total = const SaleCalculator()
        .calculate(
          draft,
          const TaxContext(
            isSellerRegistered: false,
            buyerIsRegistered: false,
            buyerIsOnAtl: null,
            province: 'punjab',
            pricesIncludeTax: false,
            ruleVersion: 'x',
          ),
        )
        .total;
    return shop.postSale(
      shop.actorNow(),
      SaleDraft(
        lines: lines,
        partyId: partyId,
        billDiscount: billDiscount,
        roundToRupee: false,
        tenders: onUdhaar
            ? const []
            : [
                TenderDraft(
                  paymentAccountId: cash,
                  mode: 'cash',
                  amount: total,
                ),
              ],
      ),
    );
  }

  Future<int> onShelf(String itemId) async =>
      (await shop.database
              .customSelect(
                'SELECT COALESCE(SUM(qty_delta_thousandths), 0) AS q FROM stock_ledger '
                'WHERE item_id = ? AND deleted_at_utc IS NULL',
                variables: [Variable<String>(itemId)],
              )
              .getSingle())
          .read<int>('q');

  /// Debits less credits on [key] across every journal line, in paisa.
  Future<int> account(String key) async =>
      (await shop.database
              .customSelect(
                'SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) AS n '
                'FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
                'WHERE a.system_key = ? AND jl.deleted_at_utc IS NULL',
                variables: [Variable<String>(key)],
              )
              .getSingle())
          .read<int>('n');

  Future<void> booksBalance() async {
    final row = await shop.database
        .customSelect(
          'SELECT COALESCE(SUM(debit_paisa), 0) AS d, '
          'COALESCE(SUM(credit_paisa), 0) AS c FROM journal_lines '
          'WHERE deleted_at_utc IS NULL',
        )
        .getSingle();
    expect(row.read<int>('d'), row.read<int>('c'));
  }

  Future<void> signInCashier() async {
    await shop.setPin(ownerId, '9999');
    final bilal = await shop.addStaff(
      name: 'Bilal',
      role: Role.cashier,
      pin: '2468',
    );
    expect(await shop.signIn(bilal, '2468'), isTrue);
  }

  group('bonus on a bill', () {
    test('ten soaps earn one free: eleven leave the shelf, the free one is a '
        'line of its own at no price, costed into the cost of the sale, and '
        'the books balance', () async {
      await shop.saveItemScheme(
        ItemScheme(
          itemId: soap,
          bonus: BonusRule(buy: Qty.units(10), free: Qty.units(1)),
        ),
      );
      final cogsBefore = await account('cogs');
      final sale = await sell(
        await withBonus([line(soap, 'Lux Soap', 10, 100)]),
      );
      expect(sale.total, const Money.rupees(1000));

      final rows = await shop.database
          .customSelect(
            'SELECT is_free_item, rate_milli_paisa, gross_paisa, '
            'discount_paisa, line_total_paisa, cost_paisa, '
            'base_qty_thousandths FROM document_lines '
            'WHERE document_id = ? ORDER BY line_no',
            variables: [Variable<String>(sale.documentId)],
          )
          .get();
      expect(rows, hasLength(2));
      final free = rows.last;
      expect(free.read<int>('is_free_item'), 1);
      expect(free.read<int>('rate_milli_paisa'), 0);
      expect(free.read<int>('gross_paisa'), 0);
      expect(free.read<int>('discount_paisa'), 0);
      expect(free.read<int>('line_total_paisa'), 0);
      expect(free.read<int>('base_qty_thousandths'), 1000);
      expect(free.read<int>('cost_paisa'), 6000, reason: 'one soap at Rs 60');

      expect(await onShelf(soap), 89000, reason: 'a hundred less eleven');
      expect(
        await account('cogs') - cogsBefore,
        66000,
        reason: 'the free soap is a cost of the sale that earned it',
      );
      expect(await account('discount_given'), 0, reason: 'not a discount');
      await booksBalance();
    });

    test('a bonus counted in cartons, and another item given free, are '
        'worked into the shelf\'s own terms', () async {
      await shop.saveItemScheme(
        ItemScheme(
          itemId: oil,
          bonus: BonusRule(
            buy: Qty.units(2),
            free: Qty.units(1),
            unitId: carton,
          ),
        ),
      );
      await shop.saveItemScheme(
        ItemScheme(
          itemId: shampoo,
          bonus: BonusRule(
            buy: Qty.units(3),
            free: Qty.units(1),
            freeItemId: soap,
          ),
        ),
      );
      final book = await shop.schemeBook();
      final oilOffer = book.bonuses[oil]!;
      expect(oilOffer.buyBase, Qty.units(48));
      expect(oilOffer.freeBase, Qty.units(24));
      expect(oilOffer.freeUnitCode, 'carton');

      // Four cartons and seven shampoos.
      final sale = await sell(
        await withBonus([
          SaleLineDraft(
            itemId: oil,
            itemName: 'Dalda Oil 1L',
            qty: Qty.units(4),
            baseQty: Qty.units(96),
            unitId: carton,
            unitCode: 'carton',
            rate: Rate.rupees(1200),
          ),
          line(shampoo, 'Sunsilk Shampoo', 7, 400),
        ]),
      );
      final free = await shop.database
          .customSelect(
            'SELECT item_name_snapshot AS n, qty_thousandths AS q, '
            'unit_code_snapshot AS u, base_qty_thousandths AS b '
            'FROM document_lines WHERE document_id = ? AND is_free_item = 1 '
            'ORDER BY line_no',
            variables: [Variable<String>(sale.documentId)],
          )
          .get();
      expect(
        [for (final r in free) r.read<String>('n')],
        ['Dalda Oil 1L', 'Lux Soap'],
      );
      expect(free.first.read<int>('q'), 2000, reason: 'two cartons');
      expect(free.first.read<String>('u'), 'carton');
      expect(free.first.read<int>('b'), 48000);
      expect(free.last.read<int>('b'), 2000, reason: 'a soap for every 3');
      expect(await onShelf(oil), 240000 - 96000 - 48000);
      expect(await onShelf(soap), 98000);
      await booksBalance();
    });

    test('a cashier rings the shop\'s bonus, but free goods past what the '
        'schemes give are the owner\'s alone', () async {
      await shop.saveItemScheme(
        ItemScheme(
          itemId: soap,
          bonus: BonusRule(buy: Qty.units(10), free: Qty.units(1)),
        ),
      );
      await signInCashier();
      await sell(await withBonus([line(soap, 'Lux Soap', 10, 100)]));

      final tooMuch = [
        line(soap, 'Lux Soap', 10, 100),
        SaleLineDraft(
          itemId: soap,
          itemName: 'Lux Soap',
          qty: Qty.units(3),
          baseQty: Qty.units(3),
          unitId: pcs,
          unitCode: 'pcs',
          rate: Rate.zero,
          isFreeItem: true,
        ),
      ];
      await expectLater(sell(tooMuch), throwsA(isA<PermissionDenied>()));
      expect(await onShelf(soap), 89000, reason: 'nothing of it was written');

      expect(await shop.signIn(ownerId, '9999'), isTrue);
      await sell(tooMuch);
      expect(await onShelf(soap), 76000);
    });

    test('a bonus-bearing bill taken back gives back only what was paid: the '
        'free soap comes back for nothing, at what it cost', () async {
      await shop.saveItemScheme(
        ItemScheme(
          itemId: soap,
          bonus: BonusRule(buy: Qty.units(10), free: Qty.units(1)),
        ),
      );
      final rashid = await shop.catalogue.addParty(
        shop.actorNow(),
        const PartyDraft(name: 'Rashid Traders'),
      );
      // Ten soaps at Rs 100 less 10%, and Rs 50 off the bill, on udhaar.
      final paid = SaleLineDraft(
        itemId: soap,
        itemName: 'Lux Soap',
        qty: Qty.units(10),
        baseQty: Qty.units(10),
        unitId: pcs,
        unitCode: 'pcs',
        rate: Rate.rupees(100),
        discountBp: 1000,
      );
      final sale = await sell(
        await withBonus([paid]),
        billDiscount: const Money.rupees(50),
        partyId: rashid,
        onUdhaar: true,
      );
      expect(sale.total, const Money.rupees(850));

      final lines = await shop.queries.returnableLines(firmId, sale.documentId);
      final freeLine = lines.singleWhere((l) => l.rate == Rate.zero);
      final paidLine = lines.singleWhere((l) => l.rate != Rate.zero);

      final freeBack = await shop.recordReturn(
        shop.actorNow(),
        ReturnDraft(
          originalDocumentId: sale.documentId,
          reason: 'Wapas',
          lines: [
            ReturnLineDraft(
              documentLineId: freeLine.documentLineId,
              qty: Qty.one,
            ),
          ],
        ),
      );
      expect(freeBack.total, Money.zero, reason: 'nothing was paid for it');
      expect(await onShelf(soap), 90000);

      final halfBack = await shop.recordReturn(
        shop.actorNow(),
        ReturnDraft(
          originalDocumentId: sale.documentId,
          reason: 'Wapas',
          lines: [
            ReturnLineDraft(
              documentLineId: paidLine.documentLineId,
              qty: Qty.units(5),
            ),
          ],
        ),
      );
      expect(
        halfBack.total,
        const Money.rupees(425),
        reason: 'half of the Rs 850 charged, never the Rs 500 list price',
      );
      expect(
        (await shop.queries.partyById(firmId, rashid))!.balance,
        const Money.rupees(425),
      );
      await booksBalance();
    });
  });

  group('the shop\'s discount on a big bill', () {
    test(
      'it rides the bill-discount path into Discount Given, split over '
      'the lines to the paisa, and a cashier rings it past their own 5%',
      () async {
        await shop.saveBillSlabs([
          BillSlab(from: const Money.rupees(5000), percentBp: 200),
          BillSlab(from: const Money.rupees(20000), percentBp: 600),
        ]);
        final book = await shop.schemeBook();
        final lines = [
          line(shampoo, 'Sunsilk Shampoo', 50, 400),
          line(soap, 'Lux Soap', 33, 100),
        ];
        final value = SchemeBook.billValueOf(lines);
        final hit = book.billSlabFor(value)!;
        expect(value, const Money.rupees(23300));
        expect(hit.discount, const Money.rupees(1398));

        await signInCashier();
        final sale = await sell(lines, billDiscount: hit.discount);
        expect(sale.total, const Money.rupees(21902));
        final split = await shop.database
            .customSelect(
              'SELECT COALESCE(SUM(discount_paisa), 0) AS d FROM document_lines '
              'WHERE document_id = ?',
              variables: [Variable<String>(sale.documentId)],
            )
            .getSingle();
        expect(split.read<int>('d'), 139800);
        expect(await account('discount_given'), 139800);

        // The slab and the cashier's own 5% on top of it: more is refused.
        await expectLater(
          sell(lines, billDiscount: hit.discount + const Money.rupees(1166)),
          throwsA(isA<PermissionDenied>()),
        );
        await sell(
          lines,
          billDiscount: hit.discount + const Money.rupees(1165),
        );
        await booksBalance();
      },
    );
  });

  group('keeping a scheme', () {
    test('only the owner keeps one; it is a settings row of the item\'s own, '
        'audited, and an empty one takes it off', () async {
      final scheme = ItemScheme(
        itemId: soap,
        bonus: BonusRule(buy: Qty.units(12), free: Qty.units(1)),
        slabs: [QtySlab(from: Qty.units(12), rate: const Rate.rupees(95))],
      );
      await shop.saveItemScheme(scheme);
      final row = await shop.database
          .customSelect(
            'SELECT value_type FROM settings WHERE setting_key = ?',
            variables: [Variable<String>('scheme.item.$soap')],
          )
          .getSingle();
      expect(row.read<String>('value_type'), 'json');
      final audit = await shop.database
          .customSelect(
            'SELECT COUNT(*) AS n FROM audit_log '
            "WHERE action_code = 'SCHEME_SET'",
          )
          .getSingle();
      expect(audit.read<int>('n'), 1);
      expect((await shop.itemScheme(soap)).bonus, scheme.bonus);
      expect((await shop.schemeBook()).slabs[soap], scheme.slabs);
      expect((await shop.itemsWithSchemes()).single.item.id, soap);

      await expectLater(
        shop.saveItemScheme(
          ItemScheme(
            itemId: soap,
            slabs: [QtySlab(from: Qty.units(12), rate: Rate.zero)],
          ),
        ),
        throwsA(isA<SchemeRefused>()),
      );

      await signInCashier();
      await expectLater(
        shop.saveItemScheme(ItemScheme(itemId: soap)),
        throwsA(isA<PermissionDenied>()),
      );
      await expectLater(
        shop.saveBillSlabs(const []),
        throwsA(isA<PermissionDenied>()),
      );

      expect(await shop.signIn(ownerId, '9999'), isTrue);
      await shop.saveItemScheme(ItemScheme(itemId: soap));
      final book = await shop.schemeBook();
      expect(book.bonuses, isEmpty);
      expect(book.slabs, isEmpty);
      expect(await shop.itemsWithSchemes(), isEmpty);
      // Put back on: the same row, not a second one.
      await shop.saveItemScheme(scheme);
      final count = await shop.database
          .customSelect(
            'SELECT COUNT(*) AS n FROM settings WHERE setting_key = ?',
            variables: [Variable<String>('scheme.item.$soap')],
          )
          .getSingle();
      expect(count.read<int>('n'), 1);
    });
  });

  group('a scheme received on a delivery', () {
    Future<String> supplier() => shop.catalogue.addParty(
      shop.actorNow(),
      const PartyDraft(name: 'Unilever Distributor', partyType: 'supplier'),
    );

    test(
      'ten cartons and one free put 264 pieces on the shelf for the ten\'s '
      'money, the free carton a row of its own, and the average falls',
      () async {
        final from = await supplier();
        final fresh = await shop.catalogue.addItem(
          shop.actorNow(),
          ItemDraft(
            name: 'Surf Excel 1kg',
            baseUnitId: pcs,
            saleRate: Rate.rupees(450),
            packs: [ItemPack(unitId: carton, size: Qty.units(24))],
          ),
        );
        final bill = await shop.recordPurchase(
          shop.actorNow(),
          PurchaseDraft(
            partyId: from,
            lines: [
              PurchaseLineDraft(
                itemId: fresh,
                itemName: 'Surf Excel 1kg',
                qty: Qty.units(10),
                baseQty: Qty.units(240),
                unitId: carton,
                unitCode: 'carton',
                rate: Rate.rupees(9240),
                freeQty: Qty.one,
                freeBaseQty: Qty.units(24),
              ),
            ],
          ),
        );
        expect(bill.total, const Money.rupees(92400));
        expect(await onShelf(fresh), 264000);
        final avg =
            (await shop.database
                    .customSelect(
                      'SELECT avg_cost_milli_paisa AS a FROM items WHERE id = ?',
                      variables: [Variable<String>(fresh)],
                    )
                    .getSingle())
                .read<int>('a');
        expect(
          avg,
          const Rate.rupees(350).inMilliPaisa,
          reason: '92,400 / 264',
        );

        final rows = await shop.database
            .customSelect(
              'SELECT is_free_item AS f, line_total_paisa AS t, cost_paisa AS c, '
              'qty_thousandths AS q FROM document_lines WHERE document_id = ? '
              'ORDER BY line_no',
              variables: [Variable<String>(bill.documentId)],
            )
            .get();
        expect([for (final r in rows) r.read<int>('f')], [0, 1]);
        expect(rows.last.read<int>('t'), 0);
        expect(rows.last.read<int>('q'), 1000, reason: 'one carton, as billed');
        expect(rows.last.read<int>('c'), 840000, reason: '24 at Rs 350');
        expect(
          await account('accounts_payable'),
          -9240000,
          reason: 'owed for what was billed, not for what came free',
        );
        await booksBalance();

        // The free carton sent back credits nothing and takes its cost with
        // it.
        final bought = await shop.queries.returnableDelivery(
          firmId,
          bill.documentId,
        );
        final freeLine = bought!.lines.singleWhere((l) => l.goodsValue.isZero);
        final back = await shop.recordPurchaseReturn(
          shop.actorNow(),
          PurchaseReturnDraft(
            originalDocumentId: bill.documentId,
            reason: 'Damaged',
            lines: [
              ReturnLineDraft(
                documentLineId: freeLine.documentLineId,
                qty: Qty.one,
              ),
            ],
          ),
        );
        expect(back.total, Money.zero);
        expect(await onShelf(fresh), 240000);
        await booksBalance();
      },
    );
  });

  group('reports', () {
    test('the item-wise discount still ties to Discount Given and shows the '
        'bonus given beside it', () async {
      await shop.saveItemScheme(
        ItemScheme(
          itemId: soap,
          bonus: BonusRule(buy: Qty.units(10), free: Qty.units(1)),
        ),
      );
      await shop.saveBillSlabs([
        BillSlab(from: const Money.rupees(1000), percentBp: 200),
      ]);
      final lines = await withBonus([line(soap, 'Lux Soap', 20, 100)]);
      final book = await shop.schemeBook();
      await sell(
        lines,
        billDiscount: book.billSlabFor(SchemeBook.billValueOf(lines))!.discount,
      );
      final today = shop.actorNow().businessDate;
      final table = await shop.reports.run(
        ReportKind.itemDiscount,
        firmId: firmId,
        period: ReportPeriod.day(today),
        today: today,
      );
      int col(String title) =>
          table.columns.indexWhere((c) => c.title == title);
      final row = table.rows.firstWhere((r) => r.cells.first == 'Lux Soap');
      expect(row.cells[col('Discount')], const Money.rupees(40));
      expect(row.cells[col('Bonus qty')], Qty.units(2));
      expect(row.cells[col('Qty sold')], Qty.units(22));
      expect(await account('discount_given'), 4000);
      final total = table.rows.firstWhere((r) => r.style == RowStyle.total);
      expect(total.cells[col('Discount')], const Money.rupees(40));
    });
  });
}
