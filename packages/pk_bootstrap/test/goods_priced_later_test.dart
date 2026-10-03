import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// Goods on the khata now, priced later; and the recovery man's round on one
/// sheet (M55) — through the services the screens use, against a real
/// database, each figure tied back to the books.
void main() {
  late FixedClock clock;
  late AppServices shop;
  late String firmId;
  late String cash;
  late String kg;

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
    kg = (await shop.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'kg').id;
  });

  tearDown(() => shop.close());

  /// An item kept by the kilo, [stock] kilos on the shelf at [costRupees].
  Future<String> item(
    String name, {
    required int rupees,
    required int costRupees,
    int stock = 100,
  }) => shop.catalogue.addItem(
    shop.actorNow(),
    ItemDraft(
      name: name,
      baseUnitId: kg,
      saleRate: Rate.rupees(rupees),
      openingStock: Qty.units(stock),
      openingRate: Rate.rupees(costRupees),
    ),
  );

  Future<String> customer(String name, {int owed = 0, String? group}) =>
      shop.catalogue.addParty(
        shop.actorNow(),
        PartyDraft(
          name: name,
          openingBalance: Money.rupees(owed),
          group: group,
        ),
      );

  SaleLineDraft kilos(String itemId, String name, int qty, {int rupees = 0}) =>
      SaleLineDraft(
        itemId: itemId,
        itemName: name,
        qty: Qty.units(qty),
        baseQty: Qty.units(qty),
        unitId: kg,
        unitCode: 'kg',
        rate: Rate.rupees(rupees),
      );

  Future<Money> owedBy(String partyId) async =>
      (await shop.queries.partyById(firmId, partyId))!.balance;

  /// What an account holds: debits less credits, every entry.
  Future<Money> heldIn(String systemKey) async {
    final rows = await shop.database
        .customSelect(
          'SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) AS held '
          'FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
          'WHERE a.system_key = ? AND jl.deleted_at_utc IS NULL',
          variables: [Variable<String>(systemKey)],
        )
        .get();
    return Money.paisa(rows.single.read<int>('held'));
  }

  Future<Qty> onShelf(String itemId) async {
    final rows = await shop.database
        .customSelect(
          'SELECT COALESCE(SUM(qty_delta_thousandths), 0) AS q '
          'FROM stock_ledger WHERE item_id = ?',
          variables: [Variable<String>(itemId)],
        )
        .get();
    return Qty.raw(rows.single.read<int>('q'));
  }

  Future<void> booksBalance() async {
    final health = await shop.checkHealth();
    expect(health.isHealthy, isTrue, reason: health.toString());
  }

  group('goods given rate later', () {
    test(
      'leave the shelf at what they cost and owe nothing until priced',
      () async {
        final ghee = await item('Ghee', rupees: 600, costRupees: 500);
        final aslam = await customer('Aslam Karyana');

        // Whatever the counter had on the line, the price is not given.
        final given = await shop.collections.giveRateLater(
          SaleDraft(
            lines: [kilos(ghee, 'Ghee', 10, rupees: 600)],
            partyId: aslam,
            partyName: 'Aslam Karyana',
          ),
        );

        final doc = await shop.database
            .customSelect(
              'SELECT doc_type, total_paisa, balance_paisa FROM documents '
              'WHERE id = ?',
              variables: [Variable<String>(given.id)],
            )
            .getSingle();
        expect(doc.read<String>('doc_type'), 'delivery_challan');
        expect(doc.read<int>('total_paisa'), 0);
        expect(doc.read<int>('balance_paisa'), 0);

        // Ten kilos left the shelf, at Rs 500 a kilo, into Goods on Challan.
        expect(await onShelf(ghee), Qty.units(90));
        expect(await heldIn('goods_on_challan'), const Money.rupees(5000));
        expect(await heldIn('inventory'), const Money.rupees(45000));
        // Nothing is owed and nothing was sold.
        expect(await owedBy(aslam), Money.zero);
        expect(await heldIn('accounts_receivable'), Money.zero);
        expect(await heldIn('sales'), Money.zero);

        final goods = await shop.collections.goodsGivenTo(aslam);
        expect(goods.single.docNo, given.docNo);
        expect(goods.single.unpricedCount, 1);
        expect(goods.single.lines.single.qty, Qty.units(10));
        expect(goods.single.lines.single.isUnpriced, isTrue);
        final waiting = await shop.collections.unpricedParties();
        expect(waiting.single.partyName, 'Aslam Karyana');
        expect(waiting.single.lines, 1);
        await booksBalance();
      },
    );

    test('priced at settlement, several on one bill: the khata owes exactly '
        'the bill, and nothing leaves the shelf twice', () async {
      final ghee = await item('Ghee', rupees: 600, costRupees: 500);
      final cheeni = await item('Cheeni', rupees: 160, costRupees: 140);
      final aslam = await customer('Aslam Karyana');

      final first = await shop.collections.giveRateLater(
        SaleDraft(
          lines: [kilos(ghee, 'Ghee', 10)],
          partyId: aslam,
          partyName: 'Aslam Karyana',
        ),
      );
      final second = await shop.collections.giveRateLater(
        SaleDraft(
          lines: [kilos(cheeni, 'Cheeni', 5), kilos(ghee, 'Ghee', 2)],
          partyId: aslam,
          partyName: 'Aslam Karyana',
        ),
      );
      expect((await shop.collections.unpricedParties()).single.lines, 3);
      expect(await heldIn('goods_on_challan'), const Money.rupees(6700));

      // Salary day: the rates agreed now, not the shelf's.
      final bill = await shop.postSale(
        shop.actorNow(),
        SaleDraft(
          lines: [
            kilos(ghee, 'Ghee', 10, rupees: 580),
            kilos(cheeni, 'Cheeni', 5, rupees: 155),
            kilos(ghee, 'Ghee', 2, rupees: 580),
          ],
          partyId: aslam,
          partyName: 'Aslam Karyana',
          roundToRupee: false,
          convertedFromId: first.id,
          alsoFromIds: [second.id],
        ),
      );

      // 12 kg at 580 and 5 kg at 155: Rs 7,735, all of it on the khata.
      expect(await owedBy(aslam), const Money.rupees(7735));
      expect(bill.docNo, startsWith('INV'));
      expect(await heldIn('accounts_receivable'), const Money.rupees(7735));
      expect(await heldIn('sales'), const Money.rupees(-7735));
      // The goods moved to cost of sales at what they left at.
      expect(await heldIn('goods_on_challan'), Money.zero);
      expect(await heldIn('cogs'), const Money.rupees(6700));
      expect(await onShelf(ghee), Qty.units(88));
      expect(await onShelf(cheeni), Qty.units(95));
      expect(await shop.collections.goodsGivenTo(aslam), isEmpty);
      expect(await shop.collections.unpricedParties(), isEmpty);
      await booksBalance();
    });

    test('a bill made from them is for exactly the goods given', () async {
      final ghee = await item('Ghee', rupees: 600, costRupees: 500);
      final aslam = await customer('Aslam Karyana');
      final given = await shop.collections.giveRateLater(
        SaleDraft(
          lines: [kilos(ghee, 'Ghee', 10)],
          partyId: aslam,
          partyName: 'Aslam Karyana',
        ),
      );

      await expectLater(
        shop.postSale(
          shop.actorNow(),
          SaleDraft(
            lines: [kilos(ghee, 'Ghee', 8, rupees: 580)],
            partyId: aslam,
            partyName: 'Aslam Karyana',
            convertedFromId: given.id,
          ),
        ),
        throwsA(isA<ChallanRefused>()),
      );
      expect(await owedBy(aslam), Money.zero);
      expect(
        (await shop.collections.goodsGivenTo(aslam)).single.docNo,
        given.docNo,
      );
    });

    test(
      'goods that came back cancel them, and they wait for no rate',
      () async {
        final ghee = await item('Ghee', rupees: 600, costRupees: 500);
        final aslam = await customer('Aslam Karyana');
        final given = await shop.collections.giveRateLater(
          SaleDraft(
            lines: [kilos(ghee, 'Ghee', 10)],
            partyId: aslam,
            partyName: 'Aslam Karyana',
          ),
        );

        await shop.voidDocument(
          shop.actorNow(),
          documentId: given.id,
          reason: 'Maal wapas',
        );

        expect(await onShelf(ghee), Qty.units(100));
        expect(await heldIn('goods_on_challan'), Money.zero);
        expect(await shop.collections.unpricedParties(), isEmpty);
        await booksBalance();
      },
    );
  });

  group('the recovery round', () {
    test('a sheet lists each customer with their open bills and what the '
        'khata says they owe, numbered from its own series', () async {
      final ghee = await item('Ghee', rupees: 600, costRupees: 500);
      final aslam = await customer(
        'Aslam Karyana',
        owed: 2000,
        group: 'Route 3',
      );
      await shop.postSale(
        shop.actorNow(),
        SaleDraft(
          lines: [kilos(ghee, 'Ghee', 5, rupees: 600)],
          partyId: aslam,
          partyName: 'Aslam Karyana',
        ),
      );
      await shop.collections.giveRateLater(
        SaleDraft(
          lines: [kilos(ghee, 'Ghee', 1)],
          partyId: aslam,
          partyName: 'Aslam Karyana',
        ),
      );
      final bilal = await customer('Bilal Store', owed: 1500, group: 'Route 3');

      final sheet = await shop.collections.makeSheet(
        SheetDraft(
          partyIds: [aslam, bilal],
          collector: 'Rafiq',
          title: 'Route 3',
        ),
      );

      expect(sheet.sheetNo, 'WS-2627-0001');
      expect(sheet.dateLocal, '2026-10-03');
      expect(sheet.madeBy, 'Malik Sahib');
      expect(sheet.expected, const Money.rupees(6500));
      final first = sheet.lines.first;
      expect(first.lineNo, 1);
      expect(first.partyName, 'Aslam Karyana');
      expect(first.group, 'Route 3');
      expect(first.due, const Money.rupees(5000));
      expect(
        [for (final b in first.bills) b.outstanding],
        [const Money.rupees(3000)],
      );
      // The opening balance is owed from before any bill.
      expect(first.earlier, const Money.rupees(2000));
      expect(first.unpriced, 1);

      // Kept, and read back whole.
      final kept = await shop.collections.sheet(sheet.id);
      expect(kept!.sheetNo, sheet.sheetNo);
      expect(kept.lines.last.due, const Money.rupees(1500));
      expect((await shop.collections.sheets()).single.id, sheet.id);
      final second = await shop.collections.makeSheet(
        SheetDraft(partyIds: [bilal], collector: 'Rafiq'),
      );
      expect(second.sheetNo, 'WS-2627-0002');
      await booksBalance();
    });

    test('paid and partial lines become receipts and the khatas fall by '
        'exactly that; a promise is written on the khata', () async {
      final aslam = await customer('Aslam Karyana', owed: 5000);
      final bilal = await customer('Bilal Store', owed: 3000);
      final chaudhry = await customer('Chaudhry Traders', owed: 2000);
      final dawood = await customer('Dawood Mart', owed: 1000);
      final ehsan = await customer('Ehsan Bros', owed: 800);
      final drawerBefore = await shop.queries.cashInDrawer(firmId);

      final sheet = await shop.collections.makeSheet(
        SheetDraft(
          partyIds: [aslam, bilal, chaudhry, dawood, ehsan],
          collector: 'Rafiq',
        ),
      );

      final round = await shop.collections.recordReturn(sheet.id, {
        1: SheetMark(outcome: CollectionOutcome.paid, paymentAccountId: cash),
        2: SheetMark(
          outcome: CollectionOutcome.partial,
          amount: const Money.rupees(1000),
          paymentAccountId: cash,
          note: 'baqi agle hafte',
        ),
        3: const SheetMark(
          outcome: CollectionOutcome.promise,
          promisedFor: '2026-10-09',
          amount: Money.rupees(2000),
        ),
        4: const SheetMark(outcome: CollectionOutcome.shopClosed),
        // Ehsan was not reached.
      });

      expect(await owedBy(aslam), Money.zero);
      expect(await owedBy(bilal), const Money.rupees(2000));
      expect(await owedBy(chaudhry), const Money.rupees(2000));
      expect(await owedBy(dawood), const Money.rupees(1000));
      expect(await owedBy(ehsan), const Money.rupees(800));
      expect(round.receipts, hasLength(2));
      expect(
        await shop.queries.cashInDrawer(firmId),
        drawerBefore + const Money.rupees(6000),
      );

      final notes = await shop.database
          .customSelect(
            "SELECT notes FROM payments WHERE direction = 'in' "
            'ORDER BY payment_no',
          )
          .get();
      expect(
        [for (final r in notes) r.read<String>('notes')],
        [
          'Wasooli ${sheet.sheetNo} · Rafiq',
          'Wasooli ${sheet.sheetNo} · Rafiq · baqi agle hafte',
        ],
      );

      // M38's promise, as the khata keeps it.
      final promise = (await shop.udhaar.queries.promisesOf(
        firmId,
        chaudhry,
      )).single;
      expect(promise.promisedFor, '2026-10-09');
      expect(promise.amount, const Money.rupees(2000));
      expect(promise.note, contains('Rafiq'));

      final settled = (await shop.collections.sheet(sheet.id))!;
      expect(settled.isSettled, isTrue);
      expect(settled.settledBy, 'Malik Sahib');
      expect(settled.expected, const Money.rupees(11800));
      expect(settled.collected, const Money.rupees(6000));
      expect(settled.cashToHandOver, const Money.rupees(6000));
      expect(settled.promised, const Money.rupees(2000));
      expect(settled.count(CollectionOutcome.shopClosed), 1);
      expect(settled.notReached, 1);
      expect(settled.lines.first.result!.paymentNo, startsWith('RCV'));
      expect(settled.lines[2].result!.promiseId, promise.id);

      // Once. A round recorded twice is every payment on it taken twice.
      await expectLater(
        shop.collections.recordReturn(sheet.id, {
          5: SheetMark(outcome: CollectionOutcome.paid, paymentAccountId: cash),
        }),
        throwsA(isA<CollectionRefused>()),
      );
      expect(await owedBy(ehsan), const Money.rupees(800));
      await booksBalance();
    });

    test('a round with one bad line writes nothing at all', () async {
      final aslam = await customer('Aslam Karyana', owed: 5000);
      final bilal = await customer('Bilal Store', owed: 3000);
      final sheet = await shop.collections.makeSheet(
        SheetDraft(partyIds: [aslam, bilal], collector: 'Rafiq'),
      );

      await expectLater(
        shop.collections.recordReturn(sheet.id, {
          1: SheetMark(outcome: CollectionOutcome.paid, paymentAccountId: cash),
          // A promise for a day already gone.
          2: const SheetMark(
            outcome: CollectionOutcome.promise,
            promisedFor: '2026-10-01',
          ),
        }),
        throwsA(isA<CollectionRefused>()),
      );
      expect(await owedBy(aslam), const Money.rupees(5000));
      expect((await shop.collections.sheet(sheet.id))!.isSettled, isFalse);
      expect(
        await shop.database
            .customSelect('SELECT COUNT(*) AS n FROM payments')
            .getSingle()
            .then((r) => r.read<int>('n')),
        0,
      );
    });

    test('a sheet is refused for a customer who owes nothing, and a cheque '
        'is taken on the khata', () async {
      final aslam = await customer('Aslam Karyana');
      await expectLater(
        shop.collections.makeSheet(
          SheetDraft(partyIds: [aslam], collector: 'Rafiq'),
        ),
        throwsA(isA<CollectionRefused>()),
      );
      await expectLater(
        shop.collections.makeSheet(
          SheetDraft(partyIds: [aslam], collector: '  '),
        ),
        throwsA(isA<CollectionRefused>()),
      );

      final bilal = await customer('Bilal Store', owed: 3000);
      final sheet = await shop.collections.makeSheet(
        SheetDraft(partyIds: [bilal], collector: 'Rafiq'),
      );
      await expectLater(
        shop.collections.recordReturn(sheet.id, {
          1: SheetMark(
            outcome: CollectionOutcome.paid,
            mode: 'cheque',
            paymentAccountId: cash,
          ),
        }),
        throwsA(isA<CollectionRefused>()),
      );
      expect(await owedBy(bilal), const Money.rupees(3000));
    });
  });
}
