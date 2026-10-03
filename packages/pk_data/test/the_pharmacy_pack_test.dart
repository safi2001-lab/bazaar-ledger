import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// The pharmacy pack (M49), against a real database.
///
/// A chemist's counter: a medicine found by its brand or its salt, and the
/// others with the same salt offered when the brand is out; the DRAP price
/// held batch by batch, refused above it in a pharmacy and allowed below; a
/// recalled batch held back from first-expiry-first-out; a Schedule drug
/// sold only on a prescription and written in the register with its batch
/// and the balance left; and expired stock sent back to the supplier it came
/// from, out of its own batch and off the supplier's khata.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late TxRunner runner;
  late DriftAppQueries queries;
  late DriftCatalogueWriter catalogue;
  late DriftPharmacyReads reads;
  late PostSaleUseCase postSale;
  late RecordPurchaseUseCase buy;
  late ActorContext actor;
  late Map<String, String> unit;
  late String supplier;
  late String otherSupplier;
  late String customer;

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 10, 3, 6));
    db = await openTestDatabase();
    final ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Shifa Medical Store',
      ownerName: 'Dr Sahib',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    actor = firm.actorAt(clock.nowUtc());
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    queries = DriftAppQueries(db);
    catalogue = DriftCatalogueWriter(runner);
    reads = DriftPharmacyReads(db);
    postSale = PostSaleUseCase(
      writer: DriftSaleWriter(runner: runner),
      shelf: DriftShelfReader(db),
      pharmacy: reads,
    );
    buy = RecordPurchaseUseCase(writer: DriftPurchaseWriter(runner: runner));
    unit = {
      for (final r in await db.customSelect('SELECT id, code FROM units').get())
        r.read<String>('code'): r.read<String>('id'),
    };
    supplier = await catalogue.addParty(
      actor,
      const PartyDraft(name: 'Medi Distributors', partyType: 'supplier'),
    );
    otherSupplier = await catalogue.addParty(
      actor,
      const PartyDraft(name: 'Shaheen Pharma', partyType: 'supplier'),
    );
    // Bills here go on the customer's khata, so no tender is needed.
    customer = await catalogue.addParty(
      actor,
      const PartyDraft(name: 'Bilal Ahmed'),
    );
  });

  tearDown(() async => db.close());

  Future<void> isAPharmacy() => runner.run(
    actor,
    (tx) => tx.update('firms', actor.firmId, {'business_kind': 'pharmacy'}),
  );

  Future<String> medicine(
    String name, {
    String? generic,
    String? strength,
    String? maker,
    ScheduleClass? schedule,
    int rupees = 40,
    int? mrp,
    int onHand = 0,
    bool batches = false,
  }) => catalogue.addItem(
    actor,
    ItemDraft(
      name: name,
      baseUnitId: unit['pcs']!,
      saleRate: Rate.rupees(rupees),
      mrp: mrp == null ? null : Money.rupees(mrp),
      openingStock: Qty.units(onHand),
      openingRate: Rate.rupees(rupees - 10),
      tracksBatch: batches,
      medicine: MedicineDetails(
        genericName: generic,
        strength: strength,
        manufacturer: maker,
        schedule: schedule,
      ),
    ),
  );

  /// [qty] of [itemId] into batch [batch], from [from].
  Future<PostedPurchase> receive(
    String itemId,
    String batch, {
    required int qty,
    required String expiry,
    int cost = 30,
    int? mrp,
    String? from,
  }) => buy(
    actor,
    PurchaseDraft(
      partyId: from ?? supplier,
      lines: [
        PurchaseLineDraft(
          itemId: itemId,
          itemName: 'Medicine',
          qty: Qty.units(qty),
          baseQty: Qty.units(qty),
          unitId: unit['pcs']!,
          unitCode: 'pcs',
          rate: Rate.rupees(cost),
          batchNo: batch,
          expiry: BusinessDate(expiry),
          mrp: mrp == null ? null : Money.rupees(mrp),
        ),
      ],
    ),
  );

  SaleLineDraft line(
    String itemId,
    int qty, {
    int rupees = 40,
    int discountBp = 0,
  }) => SaleLineDraft(
    itemId: itemId,
    itemName: 'Medicine',
    qty: Qty.units(qty),
    baseQty: Qty.units(qty),
    unitId: unit['pcs'],
    unitCode: 'pcs',
    rate: Rate.rupees(rupees),
    discountBp: discountBp,
  );

  Future<PostedSale> sell(
    List<SaleLineDraft> lines, {
    Prescription? prescription,
  }) => postSale(
    actor,
    SaleDraft(
      lines: lines,
      partyId: customer,
      partyName: 'Bilal Ahmed',
      roundToRupee: false,
      prescription: prescription,
    ),
  );

  Future<int> lotBalance(String lotNo) async =>
      (await db
              .customSelect(
                'SELECT COALESCE(SUM(s.qty_delta_thousandths), 0) AS q '
                'FROM stock_lots l LEFT JOIN stock_ledger s ON s.lot_id = l.id '
                'WHERE l.lot_no = ?',
                variables: [Variable<String>(lotNo)],
              )
              .getSingle())
          .read<int>('q');

  Future<int> count(String sql) async =>
      (await db.customSelect(sql).getSingle()).read<int>('n');

  Future<void> booksBalance() async {
    expect(await db.findLedgerImbalances(), isEmpty);
    expect(await db.findStockLedgerDrift(), isEmpty);
  }

  const rx = Prescription(
    patientName: 'Bilal Ahmed',
    patientAddress: 'Gulberg III, Lahore',
    prescriberName: 'Dr Ayesha Khan',
    prescriberRegNo: '12345-P',
    reference: 'Rx-77',
  );

  group('the pharmacy pack', () {
    test('a medicine is found by its brand or by its salt, however the salt is '
        'spelt', () async {
      final panadol = await medicine(
        'Panadol',
        generic: 'Paracetamol',
        strength: '500 mg',
      );
      await medicine('Brufen', generic: 'Ibuprofen', strength: '400 mg');
      await medicine('Surf Excel');

      Future<List<String>> found(String query) async => [
        for (final i in await queries.searchItems(actor.firmId, query: query))
          i.name,
      ];
      expect(await found('panadol'), ['Panadol']);
      expect(await found('paracetamol'), ['Panadol']);
      expect(
        await found('paracitamol'),
        ['Panadol'],
        reason: 'the salt is found however it is spelt, as a name is (M56)',
      );
      expect(await found('paracetamol 500'), ['Panadol']);
      expect(await found('ibuprofin'), ['Brufen']);
      expect(await found('surf'), ['Surf Excel']);

      final read = (await queries.itemById(actor.firmId, panadol))!;
      expect(read.medicine?.label, 'Paracetamol 500 mg');
    });

    test('the medicines with the same salt and strength are its substitutes, '
        'with their stock and price', () async {
      final panadol = await medicine(
        'Panadol',
        generic: 'Paracetamol',
        strength: '500 mg',
      );
      await medicine(
        'Calpol',
        generic: 'paracetamol',
        strength: '500mg',
        maker: 'GSK',
        onHand: 30,
        rupees: 35,
      );
      await medicine('Febrol', generic: 'Paracetamol', strength: '500 mg');
      await medicine('Panadol 250', generic: 'Paracetamol', strength: '250 mg');
      await medicine('Panadol Extra', generic: 'Paracetamol + Caffeine');

      final subs = await reads.substitutes(actor.firmId, panadol);
      expect(
        subs.map((i) => i.name),
        ['Calpol', 'Febrol'],
        reason:
            'same salt and strength, however written; the one on the shelf '
            'first; another strength or another salt is not a substitute',
      );
      expect(subs.first.stockOnHand, Qty.units(30));
      expect(subs.first.saleRate, Rate.rupees(35));
      expect(subs.first.medicine?.manufacturer, 'GSK');
    });

    test('a batch remembers the supplier it came from and the price printed '
        'on it', () async {
      final panadol = await medicine('Panadol', batches: true, mrp: 45);
      await receive(panadol, 'P1', qty: 50, expiry: '2027-06-30', mrp: 42);
      final lot = await db
          .customSelect(
            'SELECT supplier_party_id, mrp_paisa FROM stock_lots '
            "WHERE lot_no = 'P1'",
          )
          .getSingle();
      expect(lot.read<String>('supplier_party_id'), supplier);
      expect(lot.read<int>('mrp_paisa'), 4200);
    });

    test('a batch on hold is passed by first-expiry-first-out, refused by '
        'name, and sold again once let go', () async {
      final panadol = await medicine('Panadol', batches: true);
      await receive(panadol, 'OLD1', qty: 10, expiry: '2026-12-31');
      await receive(panadol, 'NEW2', qty: 10, expiry: '2027-12-31');
      final old = (await reads.lotBalances(
        panadol,
        'MAIN',
      )).singleWhere((l) => l.lotNo == 'OLD1');

      final writer = DriftPharmacyWriter(runner);
      await writer.holdBatch(actor, old.lotId, 'DRAP recall 14/2026');

      // First-expiry-first-out would take OLD1. Held, it is passed by.
      await sell([line(panadol, 6)]);
      expect(await lotBalance('OLD1'), 10000);
      expect(await lotBalance('NEW2'), 4000);

      // Past what is not held, the sale is refused by the hold's words, and
      // nothing of it is written.
      await expectLater(
        sell([line(panadol, 8)]),
        throwsA(
          isA<StockRefused>().having(
            (e) => e.reason,
            'reason',
            allOf(contains('OLD1'), contains('DRAP recall 14/2026')),
          ),
        ),
      );
      expect(await lotBalance('NEW2'), 4000);

      await writer.releaseBatch(actor, old.lotId);
      await sell([line(panadol, 8)]);
      expect(await lotBalance('OLD1'), 2000, reason: 'oldest first again');
      expect(await lotBalance('NEW2'), 4000);
      expect(
        await count(
          'SELECT COUNT(*) AS n FROM audit_log WHERE action_code IN '
          "('BATCH_HELD', 'BATCH_RELEASED')",
        ),
        2,
      );
      await booksBalance();
    });

    test(
      'above the printed price is refused for a pharmacy, batch by batch, '
      'and let through for any other shop; below is always allowed',
      () async {
        final strip = await medicine('Disprin', mrp: 50, onHand: 20);

        // A kiryana that keeps a few strips: the counter asks, the books let
        // it through.
        await sell([line(strip, 1, rupees: 55)]);

        await isAPharmacy();
        await expectLater(
          sell([line(strip, 2, rupees: 55)]),
          throwsA(
            isA<MrpRefused>()
                .having(
                  (e) => e.breaches.single.ceiling,
                  'ceiling',
                  Money.rupees(100),
                )
                .having(
                  (e) => e.breaches.single.over,
                  'over',
                  Money.rupees(10),
                ),
          ),
        );
        // At the MRP, and at "10% off MRP", it sells.
        await sell([line(strip, 2, rupees: 50)]);
        await sell([line(strip, 2, rupees: 50, discountBp: 1000)]);

        // Batch by batch: the older batch carries the older, lower price,
        // and goes first.
        final panadol = await medicine('Panadol', batches: true, mrp: 45);
        await receive(panadol, 'A1', qty: 5, expiry: '2027-01-31', mrp: 40);
        await receive(panadol, 'B2', qty: 5, expiry: '2027-12-31', mrp: 45);
        await expectLater(
          sell([line(panadol, 2, rupees: 42)]),
          throwsA(isA<MrpRefused>()),
          reason: 'Rs 42 is under the item\'s Rs 45, over batch A1\'s Rs 40',
        );
        // Seven strips: five of A1 at Rs 40 and two of B2 at Rs 45 allow
        // Rs 290.
        await sell([line(panadol, 7, rupees: 41)]);
        expect(
          (await db
                  .customSelect(
                    'SELECT COUNT(*) AS n FROM documents '
                    "WHERE doc_type = 'sale_invoice'",
                  )
                  .getSingle())
              .read<int>('n'),
          4,
        );
        await booksBalance();
      },
    );

    test('a Schedule medicine cannot be sold without patient and prescriber, '
        'and nothing of the bill is written', () async {
      final alp = await medicine(
        'Xanax 0.5',
        generic: 'Alprazolam',
        strength: '0.5 mg',
        schedule: ScheduleClass.b,
        onHand: 10,
      );
      await expectLater(
        sell([line(alp, 1)]),
        throwsA(
          isA<PrescriptionRefused>().having((e) => e.medicines, 'medicines', [
            'Xanax 0.5',
          ]),
        ),
      );
      await expectLater(
        sell(
          [line(alp, 1)],
          prescription: const Prescription(
            patientName: 'Bilal Ahmed',
            prescriberName: ' ',
            prescriberRegNo: '12345-P',
          ),
        ),
        throwsA(
          isA<PrescriptionRefused>().having((e) => e.missing, 'missing', [
            'prescriber',
          ]),
        ),
      );
      expect(
        await count(
          "SELECT COUNT(*) AS n FROM documents WHERE doc_type = 'sale_invoice'",
        ),
        0,
      );
      expect(await count('SELECT COUNT(*) AS n FROM prescriptions'), 0);

      // An ordinary medicine on its own asks nothing.
      final panadol = await medicine('Panadol', onHand: 10);
      await sell([line(panadol, 1)]);
    });

    test('a Schedule sale is in the register with its prescription, batch and '
        'running balance', () async {
      final alp = await medicine(
        'Xanax 0.5',
        generic: 'Alprazolam',
        strength: '0.5 mg',
        maker: 'Pfizer',
        schedule: ScheduleClass.b,
        batches: true,
      );
      await receive(alp, 'XB1', qty: 30, expiry: '2027-08-31');
      final panadol = await medicine('Panadol', onHand: 10);
      final sale = await sell([
        line(alp, 10),
        line(panadol, 2),
      ], prescription: rx);
      await sell([line(alp, 5)], prescription: rx);

      final rows = await db
          .customSelect(
            'SELECT document_id, item_id, schedule_class, patient_name, '
            'prescriber_name, prescriber_reg_no, prescription_ref '
            'FROM prescriptions ORDER BY created_at_utc, id',
          )
          .get();
      expect(rows, hasLength(2), reason: 'one row per Schedule line only');
      expect(rows.first.read<String>('document_id'), sale.documentId);
      expect(rows.first.read<String>('item_id'), alp);
      expect(rows.first.read<String>('schedule_class'), 'B');
      expect(rows.first.read<String>('prescriber_reg_no'), '12345-P');

      final table = await ReportEngine(DriftReportSource(db)).run(
        ReportKind.scheduleRegister,
        firmId: actor.firmId,
        period: ReportPeriod(
          const BusinessDate('2026-10-01'),
          const BusinessDate('2026-10-31'),
        ),
        today: const BusinessDate('2026-10-03'),
      );
      final entries = [
        for (final r in table.rows)
          if (r.style == RowStyle.line && r.cells[1] != null) r.cells,
      ];
      // Purchase, then the two sales: serial, sold, purchased, balance.
      expect([for (final e in entries) e[1]], [1, 2, 3]);
      expect(entries[0][9], Qty.units(30));
      expect(entries[0][10], Qty.units(30));
      expect(entries[1][3], 'Bilal Ahmed, Gulberg III, Lahore');
      expect(entries[1][4], 'Dr Ayesha Khan, Reg 12345-P, Rx Rx-77');
      expect(entries[1][5], 'Xanax 0.5');
      expect(entries[1][6], 'Pfizer');
      expect(entries[1][7], 'XB1');
      expect(entries[1][8], Qty.units(10));
      expect(entries[1][10], Qty.units(20));
      expect(entries[2][10], Qty.units(15));
      expect(
        table.rows.where((r) => r.style == RowStyle.heading).single.cells.first,
        contains('Alprazolam 0.5 mg'),
        reason: 'one page per medicine; Panadol is not on the register',
      );
    });

    test('expired stock goes back to the supplier it came from, out of its '
        'own batch and off what the shop owes, in one transaction', () async {
      final panadol = await medicine('Panadol', batches: true, mrp: 45);
      final delivery = await receive(
        panadol,
        'EXP1',
        qty: 20,
        expiry: '2026-10-20',
        cost: 30,
      );
      await receive(
        panadol,
        'FRESH',
        qty: 20,
        expiry: '2027-10-31',
        from: otherSupplier,
      );

      final near = expiriesBySupplier(
        await reads.expiringBatches(
          actor.firmId,
          before: const BusinessDate('2026-11-03'),
        ),
      );
      expect(near.single.supplierName, 'Medi Distributors');
      final batch = near.single.batches.single;
      expect(batch.lotNo, 'EXP1');
      expect(batch.qty, Qty.units(20));

      final sources = await reads.deliveriesInto([batch.lotId]);
      final from = sources[batch.lotId]!.single;
      expect(from.documentId, delivery.documentId);

      final back = await DriftPharmacyWriter(runner).returnsTogether(
        actor,
        {batch.lotId: batch.qty},
        (writer) => RecordPurchaseReturnUseCase(writer: writer)(
          actor,
          PurchaseReturnDraft(
            originalDocumentId: from.documentId,
            lines: [
              ReturnLineDraft(
                documentLineId: from.lineId,
                qty: batch.qty,
                lotId: batch.lotId,
              ),
            ],
            reason: 'Expired',
          ),
        ),
      );
      expect(back.againstBill, Money.rupees(600));
      expect(await lotBalance('EXP1'), 0, reason: 'the batch is empty');
      expect(await lotBalance('FRESH'), 20000, reason: 'and only that batch');
      final owed = await db
          .customSelect(
            'SELECT balance_paisa FROM documents WHERE id = ?',
            variables: [Variable<String>(delivery.documentId)],
          )
          .getSingle();
      expect(owed.read<int>('balance_paisa'), 0, reason: 'off the khata');
      expect(
        await reads.expiringBatches(
          actor.firmId,
          before: const BusinessDate('2026-11-03'),
        ),
        isEmpty,
      );

      // Asked again for what is no longer there, nothing is written.
      await expectLater(
        DriftPharmacyWriter(runner).returnsTogether(actor, {
          batch.lotId: batch.qty,
        }, (_) async => fail('the batch is empty, so nothing should run')),
        throwsA(isA<ReturnRefused>()),
      );
      await booksBalance();
    });

    test('a shop standing discount off the MRP is kept, and only as a '
        'percentage', () async {
      final writer = DriftPharmacyWriter(runner);
      expect((await reads.rulesFor(actor.firmId)).isPharmacy, isFalse);
      await isAPharmacy();
      await writer.setOffMrp(actor, 1000);
      final rules = await reads.rulesFor(actor.firmId);
      expect(rules.isPharmacy, isTrue);
      expect(rules.offMrpBp, 1000);
      expect(rules.mrpRule, MrpRule.block);
      expect(() => writer.setOffMrp(actor, 10001), throwsArgumentError);
    });
  });
}
