import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// A return gives back exactly what the line was charged, in the unit it was
/// sold in (M57), against a real database.
///
/// Both bugs were found by M37 and reproduced here before anything was
/// changed:
///
///  * a line sold at 10% off came back at its list price. Ten soaps at
///    Rs 100 with Rs 100 off were paid Rs 900 for, and the return gave back
///    Rs 1,000;
///  * a line sold in another unit was read as priced per base unit. A maund
///    of atta sold at Rs 5,000 was offered back as "40 maund", and taking
///    all of it back gave the customer Rs 2,00,000 for a Rs 5,000 sale.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late TxRunner runner;
  late DriftAppQueries queries;
  late PostSaleUseCase postSale;
  late PostSaleUseCase postTaxedSale;
  late RecordReturnUseCase takeBack;
  late RecordPurchaseUseCase buy;
  late RecordPurchaseReturnUseCase sendBack;
  late ActorContext actor;
  late Map<String, String> unit;
  late String soap;
  late String eggs;
  late String atta;
  late String rashid;
  late String mill;

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 10, 3, 6));
    db = await openTestDatabase();
    final ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    actor = firm.actorAt(clock.nowUtc());
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    queries = DriftAppQueries(db);
    postSale = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));
    postTaxedSale = PostSaleUseCase(
      writer: DriftSaleWriter(runner: runner),
      calculator: const SaleCalculator(taxEngine: PakistanTaxEngine()),
    );
    takeBack = RecordReturnUseCase(writer: DriftReturnWriter(runner: runner));
    buy = RecordPurchaseUseCase(writer: DriftPurchaseWriter(runner: runner));
    sendBack = RecordPurchaseReturnUseCase(
      writer: DriftPurchaseReturnWriter(runner: runner),
    );
    unit = {
      for (final r in await db.customSelect('SELECT id, code FROM units').get())
        r.read<String>('code'): r.read<String>('id'),
    };

    await runner.run(actor, (tx) async {
      soap = await tx.insert('items', {
        'name': 'Lux Soap',
        'name_search': 'lux soap',
        'base_unit_id': unit['pcs'],
        'sale_rate_milli_paisa': Rate.rupees(100).inMilliPaisa,
        'avg_cost_milli_paisa': Rate.rupees(70).inMilliPaisa,
      });
      eggs = await tx.insert('items', {
        'name': 'Anday',
        'name_search': 'anday',
        'base_unit_id': unit['pcs'],
        'sale_rate_milli_paisa': Rate.rupees(25).inMilliPaisa,
        'avg_cost_milli_paisa': Rate.rupees(20).inMilliPaisa,
      });
      atta = await tx.insert('items', {
        'name': 'Atta Chakki',
        'name_search': 'atta chakki',
        'base_unit_id': unit['kg'],
        'sale_rate_milli_paisa': Rate.rupees(125).inMilliPaisa,
        'avg_cost_milli_paisa': Rate.rupees(110).inMilliPaisa,
      });
      rashid = await tx.insert('parties', {
        'name': 'Rashid Traders',
        'name_search': 'rashid traders',
        'party_type': 'customer',
      });
      mill = await tx.insert('parties', {
        'name': 'Punjab Flour Mills',
        'name_search': 'punjab flour mills',
        'party_type': 'supplier',
      });
    });
  });

  tearDown(() async => db.close());

  SaleLineDraft soaps(int n, {int discountBp = 0}) => SaleLineDraft(
    itemId: soap,
    itemName: 'Lux Soap',
    qty: Qty.units(n),
    baseQty: Qty.units(n),
    unitId: unit['pcs'],
    unitCode: 'pcs',
    rate: Rate.rupees(100),
    discountBp: discountBp,
  );

  /// A maund is forty kilos (the seeded conversion).
  SaleLineDraft maunds(String qty, {int discountBp = 0}) => SaleLineDraft(
    itemId: atta,
    itemName: 'Atta Chakki',
    qty: Qty.parse(qty),
    baseQty: Qty.raw(Qty.parse(qty).inThousandths * 40),
    unitId: unit['maund'],
    unitCode: 'maund',
    rate: Rate.rupees(5000),
    discountBp: discountBp,
  );

  /// A dozen is twelve pieces.
  SaleLineDraft dozens(int n, {int discountBp = 0}) => SaleLineDraft(
    itemId: eggs,
    itemName: 'Anday',
    qty: Qty.units(n),
    baseQty: Qty.units(n * 12),
    unitId: unit['dozen'],
    unitCode: 'dozen',
    rate: Rate.rupees(300),
    discountBp: discountBp,
  );

  Future<PostedSale> sell(
    List<SaleLineDraft> lines, {
    Money billDiscount = Money.zero,
    bool taxed = false,
  }) => (taxed ? postTaxedSale : postSale)(
    actor,
    SaleDraft(
      partyId: rashid,
      partyName: 'Rashid Traders',
      roundToRupee: false,
      billDiscount: billDiscount,
      lines: lines,
    ),
  );

  Future<List<SoldLine>> linesOf(PostedSale sale) =>
      queries.returnableLines(firm.firmId, sale.documentId);

  Future<RecordedReturn> giveBack(PostedSale sale, SoldLine line, Qty qty) =>
      takeBack(
        actor,
        ReturnDraft(
          originalDocumentId: sale.documentId,
          reason: 'Customer ne wapas kiya',
          lines: [
            ReturnLineDraft(documentLineId: line.documentLineId, qty: qty),
          ],
        ),
      );

  Future<int> net(String key) async =>
      (await db
              .customSelect(
                'SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) '
                'AS n FROM journal_lines jl JOIN accounts a '
                'ON a.id = jl.account_id WHERE a.system_key = ?',
                variables: [Variable<String>(key)],
              )
              .getSingle())
          .read<int>('n');

  Future<int> stockOf(String item) async =>
      (await db
              .customSelect(
                'SELECT COALESCE(SUM(qty_delta_thousandths), 0) AS q '
                'FROM stock_ledger WHERE item_id = ?',
                variables: [Variable<String>(item)],
              )
              .getSingle())
          .read<int>('q');

  Future<void> booksBalance() async {
    final t = await db
        .customSelect(
          'SELECT SUM(debit_paisa) AS d, SUM(credit_paisa) AS c '
          'FROM journal_lines',
        )
        .getSingle();
    expect(t.read<int>('d'), t.read<int>('c'), reason: 'the books are out');
  }

  group('a line sold with something off', () {
    test('comes back at the Rs 900 that was paid for it, not the Rs 1,000 it '
        'listed at', () async {
      final sale = await sell([soaps(10, discountBp: 1000)]);
      expect(sale.total, const Money.rupees(900));

      final line = (await linesOf(sale)).single;
      final back = await giveBack(sale, line, line.returnable);

      expect(back.total, const Money.rupees(900));
      expect(
        (await queries.partyById(firm.firmId, rashid))!.balance,
        Money.zero,
        reason: 'the customer owed Rs 900 and was credited a different sum',
      );
      await booksBalance();
    });

    test('one of the ten comes back at the Rs 90 paid for it', () async {
      final sale = await sell([soaps(10, discountBp: 1000)]);
      final line = (await linesOf(sale)).single;

      final back = await giveBack(sale, line, Qty.one);

      expect(back.total, const Money.rupees(90));
    });

    test(
      'its share of a discount on the whole bill comes back with it',
      () async {
        // Rs 300 of soap and Rs 300 of atta, Rs 60 off the bill: Rs 30 of it
        // is the soap's, so the three soaps were paid Rs 270 for.
        final sale = await sell([
          soaps(3),
          SaleLineDraft(
            itemId: atta,
            itemName: 'Atta Chakki',
            qty: Qty.parse('2.4'),
            baseQty: Qty.parse('2.4'),
            unitId: unit['kg'],
            unitCode: 'kg',
            rate: Rate.rupees(125),
          ),
        ], billDiscount: const Money.rupees(60));
        final soapLine = (await linesOf(
          sale,
        )).firstWhere((l) => l.itemId == soap);

        final one = await giveBack(sale, soapLine, Qty.one);
        expect(one.total, const Money.rupees(90));

        final rest = (await linesOf(sale)).firstWhere((l) => l.itemId == soap);
        final two = await giveBack(sale, rest, rest.returnable);
        expect(two.total, const Money.rupees(180));
        await booksBalance();
      },
    );

    test(
      'the discount account is not left holding the part that came back',
      () async {
        // The sale credited Sales gross and debited Discount Given; the
        // return mirrors both, so a line that came back whole leaves
        // nothing behind in either.
        final sale = await sell([soaps(10, discountBp: 1000)]);
        expect(await net('discount_given'), 10000);
        final line = (await linesOf(sale)).single;

        await giveBack(sale, line, line.returnable);

        expect(await net('discount_given'), 0);
        expect(await net('sales') + await net('sales_returns'), 0);
        expect(await net('accounts_receivable'), 0);
        expect(await net('inventory') + await net('cogs'), 0);
        await booksBalance();
      },
    );
  });

  group('a line sold in another unit', () {
    test(
      'a maund comes back as a maund: Rs 5,000 and 40 kg, not Rs 2,00,000',
      () async {
        final sale = await sell([maunds('1')]);
        final line = (await linesOf(sale)).single;
        expect(line.returnable, Qty.one, reason: 'offered as 40 maund');
        expect(line.unitCode, 'maund');

        final back = await giveBack(sale, line, line.returnable);

        expect(back.total, const Money.rupees(5000));
        expect(await stockOf(atta), 0, reason: 'all forty kilos are back');
        final row = await db
            .customSelect(
              'SELECT qty_thousandths, base_qty_thousandths, '
              'unit_code_snapshot, rate_milli_paisa FROM document_lines '
              'WHERE document_id = ?',
              variables: [Variable<String>(back.documentId)],
            )
            .getSingle();
        expect(row.read<int>('qty_thousandths'), 1000);
        expect(row.read<int>('base_qty_thousandths'), 40000);
        expect(row.read<String>('unit_code_snapshot'), 'maund');
        expect(
          row.read<int>('rate_milli_paisa'),
          Rate.rupees(5000).inMilliPaisa,
        );
      },
    );

    test('half a maund comes back as 20 kg for Rs 2,500', () async {
      final sale = await sell([maunds('1')]);
      final line = (await linesOf(sale)).single;

      final back = await giveBack(sale, line, Qty.parse('0.5'));

      expect(back.total, const Money.rupees(2500));
      expect(await stockOf(atta), -20000);
      expect((await linesOf(sale)).single.returnable, Qty.parse('0.5'));
    });

    test('a dozen comes back by the dozen, at the dozen paid for', () async {
      // Two dozen at Rs 300 with 10% off: Rs 540, Rs 270 a dozen.
      final sale = await sell([dozens(2, discountBp: 1000)]);
      final line = (await linesOf(sale)).single;
      expect(line.returnable, Qty.units(2));

      final first = await giveBack(sale, line, Qty.one);
      expect(first.total, const Money.rupees(270));
      expect(await stockOf(eggs), -12000);

      final second = await giveBack(
        sale,
        (await linesOf(sale)).single,
        Qty.one,
      );
      expect(second.total, const Money.rupees(270));
      expect(await stockOf(eggs), 0);
      expect(await net('accounts_receivable'), 0);
      await booksBalance();
    });

    test('the limit holds in the unit it was sold in, across visits', () async {
      final sale = await sell([maunds('1')]);
      await giveBack(sale, (await linesOf(sale)).single, Qty.parse('0.5'));

      final left = (await linesOf(sale)).single;
      await expectLater(
        giveBack(sale, left, Qty.one),
        throwsA(isA<ReturnRefused>()),
      );
      await giveBack(sale, left, Qty.parse('0.5'));
      final none = (await linesOf(sale)).single;
      expect(none.returnable, Qty.zero);
      await expectLater(
        giveBack(sale, none, Qty.parse('0.001')),
        throwsA(isA<ReturnRefused>()),
      );
      expect(await stockOf(atta), 0);
    });
  });

  group('part returns of one line', () {
    test('add up to exactly what it was charged, to the paisa', () async {
      // Three soaps at Rs 100 with Rs 0.01 off the bill... and then some:
      // Rs 299.99 across three does not split evenly, and three returns of
      // one must still give back Rs 299.99 between them.
      final sale = await sell([soaps(3)], billDiscount: const Money.paisa(1));
      expect(sale.total, const Money.paisa(29999));

      var given = Money.zero;
      for (var i = 0; i < 3; i++) {
        final line = (await linesOf(sale)).single;
        given += (await giveBack(sale, line, Qty.one)).total;
      }

      expect(given, const Money.paisa(29999));
      expect(await net('discount_given'), 0);
      expect(await net('accounts_receivable'), 0);
      expect(await net('inventory') + await net('cogs'), 0);
      await booksBalance();
    });
  });

  group('a taxed line with something off, sold in maunds', () {
    test('gives back every paisa of both taxes and the discount', () async {
      await runner.run(actor, (tx) async {
        await tx.update('firms', firm.firmId, {'is_sales_tax_registered': 1});
      });
      // Two maunds at Rs 5,000 less 5%, to a named unregistered buyer:
      // 18% sales tax and 4% further tax on Rs 9,500.
      final sale = await sell([maunds('2', discountBp: 500)], taxed: true);
      expect(sale.total, const Money.rupees(11590));

      final first = await giveBack(
        sale,
        (await linesOf(sale)).single,
        Qty.parse('0.5'),
      );
      expect(first.total, const Money.paisa(289750));
      final rest = (await linesOf(sale)).single;
      final second = await giveBack(sale, rest, rest.returnable);

      expect(first.total + second.total, sale.total);
      expect(await net('output_tax'), 0);
      expect(await net('further_tax_payable'), 0);
      expect(await net('discount_given'), 0);
      expect(await net('sales') + await net('sales_returns'), 0);
      expect(await stockOf(atta), 0);
      await booksBalance();
    });

    test('prices that include the tax give it back from inside', () async {
      await runner.run(actor, (tx) async {
        await tx.update('firms', firm.firmId, {
          'is_sales_tax_registered': 1,
          'prices_include_tax': 1,
        });
        await tx.update('parties', rashid, {
          'buyer_registration_type': 'registered',
          'is_on_atl': 1,
        });
      });
      final sale = await sell([maunds('1', discountBp: 1000)], taxed: true);
      expect(sale.total, const Money.rupees(4500));

      final line = (await linesOf(sale)).single;
      final back = await giveBack(sale, line, line.returnable);

      expect(back.total, const Money.rupees(4500));
      expect(await net('output_tax'), 0);
      expect(await net('discount_given'), 0);
      expect(await net('sales') + await net('sales_returns'), 0);
      await booksBalance();
    });
  });

  group('the paper a return prints', () {
    test('shows the maund, the discount and what came back', () async {
      final sale = await sell([maunds('1', discountBp: 1000)]);
      final line = (await linesOf(sale)).single;
      final back = await giveBack(sale, line, Qty.parse('0.5'));

      final paper = (await queries.receiptFor(firm.firmId, back.documentId))!;

      expect(paper.docTitle, 'Sale Return');
      final printed = paper.lines.single;
      expect(printed.qtyDisplay, '0.5');
      expect(printed.unitCode, 'maund');
      expect(printed.amount, const Money.rupees(2500));
      expect(printed.discount, const Money.rupees(250));
      expect(paper.subtotal, const Money.rupees(2500));
      expect(paper.discount, const Money.rupees(250));
      expect(paper.total, const Money.rupees(2250));
    });
  });

  group('a delivery bought in maunds', () {
    Future<String> deliver() async => (await buy(
      actor,
      PurchaseDraft(
        partyId: mill,
        lines: [
          PurchaseLineDraft(
            itemId: atta,
            itemName: 'Atta Chakki',
            qty: Qty.units(2),
            baseQty: Qty.units(80),
            unitId: unit['maund']!,
            unitCode: 'maund',
            rate: Rate.rupees(4800),
          ),
        ],
      ),
    )).documentId;

    test('goes back by the maund, at the maund it was billed at', () async {
      final delivery = await deliver();
      final line = (await queries.returnableDelivery(
        firm.firmId,
        delivery,
      ))!.lines.single;
      expect(line.returnable, Qty.units(2), reason: 'offered as 80 maund');

      final back = await sendBack(
        actor,
        PurchaseReturnDraft(
          originalDocumentId: delivery,
          reason: 'Ek bori geeli thi',
          lines: [
            ReturnLineDraft(documentLineId: line.documentLineId, qty: Qty.one),
          ],
        ),
      );

      expect(back.total, const Money.rupees(4800));
      expect(await stockOf(atta), 40000);
      final row = await db
          .customSelect(
            'SELECT qty_thousandths, base_qty_thousandths, unit_code_snapshot '
            'FROM document_lines WHERE document_id = ?',
            variables: [Variable<String>(back.documentId)],
          )
          .getSingle();
      expect(row.read<int>('qty_thousandths'), 1000);
      expect(row.read<int>('base_qty_thousandths'), 40000);
      expect(row.read<String>('unit_code_snapshot'), 'maund');

      final left = (await queries.returnableDelivery(
        firm.firmId,
        delivery,
      ))!.lines.single;
      expect(left.returnable, Qty.one);
      await sendBack(
        actor,
        PurchaseReturnDraft(
          originalDocumentId: delivery,
          reason: 'Doosri bhi',
          lines: [
            ReturnLineDraft(documentLineId: left.documentLineId, qty: Qty.one),
          ],
        ),
      );
      expect(await stockOf(atta), 0);
      expect(await net('inventory'), 0);
      expect(await net('accounts_payable'), 0);
      await booksBalance();
    });
  });
}
