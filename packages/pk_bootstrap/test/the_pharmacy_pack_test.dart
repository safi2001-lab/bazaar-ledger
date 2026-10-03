import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// One clock for both phones, a millisecond on at every look.
final class _Ticking implements Clock {
  DateTime _t = DateTime.utc(2026, 10, 3, 5);

  @override
  DateTime nowUtc() => _t = _t.add(const Duration(milliseconds: 1));
}

/// The pharmacy pack through the services the app is built on (M49): an
/// expiry return to one supplier across the deliveries its batches came in
/// on, the medicine, its held batch and its register reaching the other
/// counter over a real socket, and who may do what.
void main() {
  late _Ticking clock;
  late AppServices master;
  late String firmId;
  late String pcs;
  late String cash;
  late String medi;
  late String shaheen;
  late String customer;

  setUp(() async {
    clock = _Ticking();
    master = await openInMemoryServices(clock: clock);
    await master.setUpShop(
      shopName: 'Shifa Medical Store',
      ownerName: 'Dr Sahib',
      deviceLabel: 'Master',
    );
    await master.updateFirm({'business_kind': 'pharmacy'});
    firmId = (await master.queries.currentFirm())!.id;
    pcs = (await master.queries.units(
      firmId,
    )).singleWhere((u) => u.code == 'pcs').id;
    cash = (await master.queries.paymentAccounts(
      firmId,
    )).firstWhere((a) => a.modeLabel == 'cash').id;
    medi = await master.catalogue.addParty(
      master.actorNow(),
      const PartyDraft(name: 'Medi Distributors', partyType: 'supplier'),
    );
    shaheen = await master.catalogue.addParty(
      master.actorNow(),
      const PartyDraft(name: 'Shaheen Pharma', partyType: 'supplier'),
    );
    customer = await master.catalogue.addParty(
      master.actorNow(),
      const PartyDraft(name: 'Bilal Ahmed'),
    );
  });

  tearDown(() => master.close());

  Future<String> medicine(
    String name, {
    String? generic,
    String? strength,
    ScheduleClass? schedule,
    int? mrp,
    bool batches = true,
    int onHand = 0,
  }) => master.catalogue.addItem(
    master.actorNow(),
    ItemDraft(
      name: name,
      baseUnitId: pcs,
      saleRate: Rate.rupees(mrp ?? 40),
      mrp: mrp == null ? null : Money.rupees(mrp),
      tracksBatch: batches,
      openingStock: Qty.units(onHand),
      openingRate: Rate.rupees(20),
      medicine: MedicineDetails(
        genericName: generic,
        strength: strength,
        schedule: schedule,
      ),
    ),
  );

  Future<PostedPurchase> receive(
    String itemId,
    String batch, {
    required String from,
    required String expiry,
    int qty = 20,
    int cost = 30,
    bool paid = false,
  }) => master.recordPurchase(
    master.actorNow(),
    PurchaseDraft(
      partyId: from,
      paid: paid ? Money.rupees(qty * cost) : Money.zero,
      paymentAccountId: paid ? cash : null,
      lines: [
        PurchaseLineDraft(
          itemId: itemId,
          itemName: 'Medicine',
          qty: Qty.units(qty),
          baseQty: Qty.units(qty),
          unitId: pcs,
          unitCode: 'pcs',
          rate: Rate.rupees(cost),
          batchNo: batch,
          expiry: BusinessDate(expiry),
        ),
      ],
    ),
  );

  Future<int> inLot(AppServices phone, String lotNo) async =>
      (await phone.database
              .customSelect(
                'SELECT COALESCE(SUM(s.qty_delta_thousandths), 0) AS q '
                'FROM stock_lots l LEFT JOIN stock_ledger s ON s.lot_id = l.id '
                'WHERE l.lot_no = ?',
                variables: [Variable<String>(lotNo)],
              )
              .getSingle())
          .read<int>('q');

  Future<Money> owedTo(String supplier) async =>
      (await master.queries.partyById(firmId, supplier))!.payable;

  group('the pharmacy pack', () {
    test('an expiry return per supplier credits the supplier and empties the '
        'batch', () async {
      final panadol = await medicine('Panadol', generic: 'Paracetamol');
      // Two deliveries from Medi: one on credit, one paid at the door. And
      // one from Shaheen that is nowhere near its date.
      await receive(panadol, 'EXP1', from: medi, expiry: '2026-10-20');
      await receive(
        panadol,
        'EXP2',
        from: medi,
        expiry: '2026-10-25',
        qty: 10,
        paid: true,
      );
      await receive(panadol, 'FRESH', from: shaheen, expiry: '2027-10-31');
      expect(await owedTo(medi), Money.rupees(600));

      final near = await master.pharmacy.nearExpiry();
      expect(near.single.supplierId, medi, reason: 'grouped by supplier');
      expect([for (final b in near.single.batches) b.lotNo], ['EXP1', 'EXP2']);

      final done = await master.pharmacy.returnToSupplier(
        medi,
        near.single.batches,
        reason: 'Expired',
      );
      expect(done.returnNos, hasLength(2), reason: 'one per delivery');
      expect(
        done.credited,
        Money.rupees(600),
        reason: "the delivery still owed comes off Medi's khata",
      );
      expect(
        done.refunded,
        Money.rupees(300),
        reason: 'the paid delivery is handed back in cash, as M5 has it',
      );
      expect(await owedTo(medi), Money.zero);
      expect(await inLot(master, 'EXP1'), 0);
      expect(await inLot(master, 'EXP2'), 0);
      expect(await inLot(master, 'FRESH'), 20000);
      expect(await master.pharmacy.nearExpiry(), isEmpty);

      final note = expiryReturnNote(
        shopName: 'Shifa Medical Store',
        supplier: 'Medi Distributors',
        date: const BusinessDate('2026-10-03'),
        done: done,
      );
      expect(note.rows.where((r) => r.style == RowStyle.line), hasLength(2));
      expect(note.totals.single.cells.last, Money.rupees(900));

      final health = await master.checkHealth();
      expect(health.isHealthy, isTrue, reason: health.toString());
    });

    test('a batch from another supplier cannot ride on the return, and '
        'nothing is written', () async {
      final panadol = await medicine('Panadol');
      await receive(panadol, 'EXP1', from: medi, expiry: '2026-10-20');
      await receive(panadol, 'EXP9', from: shaheen, expiry: '2026-10-21');
      final all = [
        for (final g in await master.pharmacy.nearExpiry()) ...g.batches,
      ];
      await expectLater(
        master.pharmacy.returnToSupplier(medi, all, reason: 'Expired'),
        throwsA(isA<ReturnRefused>()),
      );
      expect(await inLot(master, 'EXP1'), 20000);
    });

    test('the medicine, its held batch and its register reach the other '
        'counter', () async {
      final xanax = await medicine(
        'Xanax 0.5',
        generic: 'Alprazolam',
        strength: '0.5 mg',
        schedule: ScheduleClass.d,
      );
      await receive(xanax, 'X1', from: medi, expiry: '2027-03-31');
      await receive(xanax, 'X2', from: medi, expiry: '2027-09-30');
      final lots = await master.queries.lotsOnHand(firmId, itemId: xanax);
      await master.pharmacy.holdBatch(
        lots.singleWhere((l) => l.lotNo == 'X1').lotId,
        'Damaged carton',
      );
      await master.postSale(
        master.actorNow(),
        SaleDraft(
          partyId: customer,
          partyName: 'Bilal Ahmed',
          lines: [
            SaleLineDraft(
              itemId: xanax,
              itemName: 'Xanax 0.5',
              qty: Qty.units(2),
              baseQty: Qty.units(2),
              unitId: pcs,
              unitCode: 'pcs',
              rate: Rate.rupees(40),
            ),
          ],
          prescription: const Prescription(
            patientName: 'Bilal Ahmed',
            prescriberName: 'Dr Ayesha Khan',
            prescriberRegNo: '12345-P',
          ),
        ),
      );

      final port = await master.sync.startHosting(
        port: 0,
        address: InternetAddress.loopbackIPv4,
      );
      final counter = await openInMemoryServices(clock: clock);
      addTearDown(counter.close);
      await counter.sync.join(
        host: '127.0.0.1',
        port: port,
        code: master.sync.openJoining(),
        label: 'Counter 2',
      );

      final found = await counter.queries.searchItems(
        firmId,
        query: 'alprazolam',
      );
      expect(found.single.name, 'Xanax 0.5');
      expect(found.single.medicine?.schedule, ScheduleClass.d);
      final there = await counter.queries.lotsOnHand(firmId, itemId: xanax);
      expect(
        there.singleWhere((l) => l.lotNo == 'X1').holdReason,
        'Damaged carton',
      );
      expect(
        there.singleWhere((l) => l.lotNo == 'X2').qty,
        Qty.units(18),
        reason: 'the sale passed the held batch by, on the master',
      );
      final register = await counter.reports.run(
        ReportKind.scheduleRegister,
        firmId: firmId,
        period: ReportPeriod(
          const BusinessDate('2026-10-01'),
          const BusinessDate('2026-10-31'),
        ),
        today: const BusinessDate('2026-10-03'),
      );
      expect(
        register.rows.any((r) => r.cells[4] == 'Dr Ayesha Khan, Reg 12345-P'),
        isTrue,
        reason: 'the prescription travelled with the bill',
      );
      final health = await counter.checkHealth();
      expect(health.isHealthy, isTrue, reason: health.toString());
    });

    test("only the owner sets the shop's discount off the MRP; a cashier "
        'sells at it, and may not hold a batch', () async {
      final disprin = await medicine(
        'Disprin',
        mrp: 50,
        batches: false,
        onHand: 20,
      );
      final panadol = await medicine('Panadol');
      await receive(panadol, 'P1', from: medi, expiry: '2027-03-31');
      await master.pharmacy.setOffMrp(1000);
      expect((await master.pharmacy.rules()).offMrpBp, 1000);

      await master.setPin(master.currentUser!.id, '9999');
      final bilal = await master.addStaff(
        name: 'Bilal',
        role: Role.cashier,
        pin: '2468',
      );
      expect(await master.signIn(bilal, '2468'), isTrue);

      await expectLater(
        master.pharmacy.setOffMrp(2000),
        throwsA(isA<PermissionDenied>()),
      );
      final lot = (await master.queries.lotsOnHand(firmId)).single;
      await expectLater(
        master.pharmacy.holdBatch(lot.lotId, 'Recall'),
        throwsA(isA<PermissionDenied>()),
      );

      // 10% off is twice what a cashier may give on his own, and it is the
      // shop's, so it goes through.
      final sold = await master.postSale(
        master.actorNow(),
        SaleDraft(
          lines: [
            SaleLineDraft(
              itemId: disprin,
              itemName: 'Disprin',
              qty: Qty.units(2),
              baseQty: Qty.units(2),
              unitId: pcs,
              unitCode: 'pcs',
              rate: Rate.rupees(50),
              discountBp: 1000,
            ),
          ],
          tenders: [
            TenderDraft(
              paymentAccountId: cash,
              mode: 'cash',
              amount: Money.rupees(90),
            ),
          ],
          roundToRupee: false,
        ),
      );
      expect(sold.total, Money.rupees(90));
    });
  });
}
