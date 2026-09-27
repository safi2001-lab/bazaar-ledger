import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// Batches with expiry, and serial numbers, against a real database.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late ActorContext actor;
  late TxRunner runner;
  late PostSaleUseCase sell;
  late RecordPurchaseUseCase buy;
  late String pcs;
  late String panadol;
  late String phone;
  late String supplier;
  late String cash;

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 9, 26, 9, 15));
    db = await openTestDatabase();
    final ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Shifa Pharmacy',
      ownerName: 'Dr Anwar',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    actor = firm.actorAt(clock.nowUtc());
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    sell = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));
    buy = RecordPurchaseUseCase(writer: DriftPurchaseWriter(runner: runner));
    pcs =
        (await db
                .customSelect("SELECT id FROM units WHERE code = 'pcs'")
                .getSingle())
            .read<String>('id');
    final catalogue = DriftCatalogueWriter(runner);
    panadol = await catalogue.addItem(
      actor,
      ItemDraft(
        name: 'Panadol strip',
        baseUnitId: pcs,
        saleRate: Rate.rupees(40),
        tracksBatch: true,
      ),
    );
    phone = await catalogue.addItem(
      actor,
      ItemDraft(
        name: 'Tecno Spark',
        baseUnitId: pcs,
        saleRate: Rate.rupees(30000),
        tracksSerial: true,
      ),
    );
    cash = (await DriftAppQueries(
      db,
    ).paymentAccounts(firm.firmId)).firstWhere((a) => a.modeLabel == 'cash').id;
    supplier = await catalogue.addParty(
      actor,
      const PartyDraft(name: 'Medi Distributors', partyType: 'supplier'),
    );
  });

  tearDown(() async => db.close());

  Future<void> receive(
    String itemId,
    int units, {
    String? batch,
    String? expiry,
    List<String> serials = const [],
  }) => buy(
    actor,
    PurchaseDraft(
      partyId: supplier,
      lines: [
        PurchaseLineDraft(
          itemId: itemId,
          itemName: itemId == panadol ? 'Panadol strip' : 'Tecno Spark',
          qty: Qty.units(units),
          baseQty: Qty.units(units),
          unitId: pcs,
          unitCode: 'pcs',
          rate: Rate.rupees(itemId == panadol ? 30 : 25000),
          batchNo: batch,
          expiry: expiry == null ? null : BusinessDate(expiry),
          serials: serials,
        ),
      ],
    ),
  ).then((_) {});

  Future<void> ring(String itemId, int units, {String? lotId}) => sell(
    actor,
    SaleDraft(
      lines: [
        SaleLineDraft(
          itemId: itemId,
          itemName: 'x',
          qty: Qty.units(units),
          baseQty: Qty.units(units),
          unitCode: 'pcs',
          rate: Rate.rupees(40),
          lotId: lotId,
        ),
      ],
      tenders: [
        TenderDraft(
          paymentAccountId: cash,
          mode: 'cash',
          amount: Money.rupees(40 * units),
        ),
      ],
      roundToRupee: false,
    ),
  ).then((_) {});

  Future<Map<String, int>> onHandByLot(String itemId) async => {
    for (final r
        in await db
            .customSelect(
              'SELECT COALESCE(l.lot_no, \'-\') AS lot, '
              'SUM(s.qty_delta_thousandths) AS q FROM stock_ledger s '
              'LEFT JOIN stock_lots l ON l.id = s.lot_id '
              "WHERE s.item_id = '$itemId' GROUP BY s.lot_id",
            )
            .get())
      r.read<String>('lot'): r.read<int>('q') ~/ 1000,
  };

  test('a delivery keeps each batch with its expiry', () async {
    await receive(panadol, 10, batch: 'B1', expiry: '2026-12-31');
    final lot = await db
        .customSelect('SELECT lot_no, expiry_date_local FROM stock_lots')
        .getSingle();
    expect(lot.data, {'lot_no': 'B1', 'expiry_date_local': '2026-12-31'});
    expect(await onHandByLot(panadol), {'B1': 10});
  });

  test('the counter sells the batch that expires first', () async {
    await receive(panadol, 20, batch: 'B2', expiry: '2027-06-30');
    await receive(panadol, 10, batch: 'B1', expiry: '2026-12-31');

    await ring(panadol, 15);

    expect(await onHandByLot(panadol), {'B1': 0, 'B2': 15});
  });

  test('an expired batch is not sold', () async {
    await receive(panadol, 10, batch: 'OLD', expiry: '2026-09-01');
    await expectLater(ring(panadol, 1), throwsA(isA<StockRefused>()));
    expect(await onHandByLot(panadol), {'OLD': 10});
  });

  test('a phone comes in by IMEI and goes out by the one scanned', () async {
    await receive(phone, 2, serials: ['356938035643809', '356938035643817']);
    final lots = {
      for (final r
          in await db.customSelect('SELECT id, lot_no FROM stock_lots').get())
        r.read<String>('lot_no'): r.read<String>('id'),
    };

    await expectLater(ring(phone, 1), throwsA(isA<StockRefused>()));
    await ring(phone, 1, lotId: lots['356938035643809']);
    expect(await onHandByLot(phone), {
      '356938035643809': 0,
      '356938035643817': 1,
    });
    await expectLater(
      ring(phone, 1, lotId: lots['356938035643809']),
      throwsA(isA<StockRefused>()),
      reason: 'the same phone cannot be sold twice',
    );
  });

  test('a delivery of phones names one IMEI per phone', () async {
    await expectLater(
      receive(phone, 2, serials: ['356938035643809']),
      throwsA(isA<StockRefused>()),
    );
    await expectLater(
      receive(phone, 2, serials: ['356938035643809', '356938035643809']),
      throwsA(isA<StockRefused>()),
    );
  });

  test(
    'goods moved to the godown leave the shop floor, batch and all',
    () async {
      await receive(panadol, 20, batch: 'B1', expiry: '2026-12-31');
      await DriftCatalogueWriter(runner).transferStock(
        actor,
        StockTransferDraft(
          itemId: panadol,
          qty: Qty.units(15),
          from: 'MAIN',
          to: 'GODOWN',
        ),
      );
      final queries = DriftAppQueries(db);
      expect(await queries.stockByLocation(firm.firmId, panadol), {
        'MAIN': Qty.units(5),
        'GODOWN': Qty.units(15),
      });
      expect(await queries.stockLocations(firm.firmId), ['MAIN', 'GODOWN']);
      expect(
        (await queries.lotsOnHand(firm.firmId, itemId: panadol)).single.qty,
        Qty.units(20),
        reason: 'still one batch, now in two places',
      );
      await expectLater(ring(panadol, 6), completes);
      expect(await queries.stockByLocation(firm.firmId, panadol), {
        'MAIN': Qty.units(-1),
        'GODOWN': Qty.units(15),
      });
    },
  );

  test('more than is there cannot be moved', () async {
    await receive(panadol, 5, batch: 'B1', expiry: '2026-12-31');
    await expectLater(
      DriftCatalogueWriter(runner).transferStock(
        actor,
        StockTransferDraft(
          itemId: panadol,
          qty: Qty.units(6),
          from: 'MAIN',
          to: 'GODOWN',
        ),
      ),
      throwsA(isA<StockRefused>()),
    );
  });

  test('a phone is found at the counter by its IMEI', () async {
    await receive(phone, 1, serials: ['356938035643809']);
    final queries = DriftAppQueries(db);
    final found = await queries.serialOnHand(firm.firmId, '356938035643809');
    expect(found!.itemId, phone);
    await ring(phone, 1, lotId: found.lotId);
    expect(await queries.serialOnHand(firm.firmId, '356938035643809'), isNull);
  });

  test('an expired batch cannot be sold even when picked by hand', () async {
    await receive(panadol, 10, batch: 'OLD', expiry: '2026-09-01');
    final lot = (await DriftAppQueries(db).lotsOnHand(firm.firmId)).single;
    await expectLater(
      ring(panadol, 1, lotId: lot.lotId),
      throwsA(isA<StockRefused>()),
    );
  });

  test('the expiry list shows what to pull off the shelf', () async {
    await receive(panadol, 10, batch: 'OLD', expiry: '2026-09-01');
    await receive(panadol, 10, batch: 'NEW', expiry: '2028-01-31');
    final t = await ReportEngine(DriftReportSource(db)).run(
      ReportKind.expiry,
      firmId: firm.firmId,
      period: ReportPeriod.day(actor.businessDate),
      today: actor.businessDate,
    );
    expect(t.rows.first.cells.sublist(0, 3), [
      'Panadol strip',
      'OLD',
      '2026-09-01',
    ]);
    expect(t.rows, hasLength(2), reason: 'NEW is years away');
  });
}
