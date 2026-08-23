import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// The ageing report, against a real database.
///
/// The domain tests prove the buckets. These prove the SQL agrees with them —
/// which matters because the bucketing is done in SQL for a wholesaler with
/// tens of thousands of open bills, and two implementations of the same
/// arithmetic is two answers to the question a shop chases money on.
void main() {
  late AppDatabase db;
  late UlidGenerator ids;
  late FirstRunResult firm;
  late TxRunner runner;
  late DriftAppQueries queries;
  late PostSaleUseCase postSale;
  late String pcsUnitId;
  late String itemId;

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 8, 23, 9, 15));
    db = await openTestDatabase();
    ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    queries = DriftAppQueries(db);
    postSale = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));

    pcsUnitId =
        (await db.customSelect("SELECT id FROM units WHERE code = 'pcs'").get())
            .first
            .read<String>('id');

    await runner.run(firm.actorAt(clock.nowUtc()), (tx) async {
      itemId = await tx.insert('items', {
        'name': 'Cooking Oil 5L',
        'name_search': 'cooking oil 5l',
        'base_unit_id': pcsUnitId,
        'sale_rate_milli_paisa': Rate.rupees(1000).inMilliPaisa,
      });
    });
  });

  tearDown(() async => db.close());

  Future<String> customer(String name) => runner.run(
    firm.actorAt(DateTime.utc(2026, 8, 23, 9)),
    (tx) => tx.insert('parties', {
      'name': name,
      'name_search': name.toLowerCase(),
      'party_type': 'customer',
    }),
  );

  /// A credit bill of [rupees] dated [onDate].
  Future<String> udhaar(String partyId, int rupees, String onDate) async {
    final parts = onDate.split('-').map(int.parse).toList();
    final posted = await postSale(
      ActorContext(
        firmId: firm.firmId,
        userId: firm.ownerUserId,
        deviceId: firm.deviceId,
        startedAtUtc: DateTime.utc(parts[0], parts[1], parts[2], 9),
      ),
      SaleDraft(
        partyId: partyId,
        lines: [
          SaleLineDraft(
            itemId: itemId,
            itemName: 'Cooking Oil 5L',
            qty: Qty.units(1),
            baseQty: Qty.units(1),
            unitId: pcsUnitId,
            unitCode: 'pcs',
            rate: Rate.rupees(rupees),
          ),
        ],
        tenders: const [],
      ),
    );
    return posted.documentId;
  }

  const today = '2026-08-23';

  test('a shop with nothing out reports every bucket at zero', () async {
    final aging = await queries.aging(firm.firmId, asOfDateLocal: today);

    expect(aging.isClear, isTrue);
    expect(aging.byBucket.keys, containsAll(AgeBucket.values));
  });

  test('bills land in the bucket their date puts them in', () async {
    final rashid = await customer('Rashid Traders');
    await udhaar(rashid, 1000, '2026-08-20'); // 3 days
    await udhaar(rashid, 2000, '2026-07-10'); // 44 days
    await udhaar(rashid, 3000, '2026-06-10'); // 74 days
    await udhaar(rashid, 4000, '2026-01-05'); // 230 days

    final aging = await queries.aging(firm.firmId, asOfDateLocal: today);

    expect(aging[AgeBucket.current], const Money.rupees(1000));
    expect(aging[AgeBucket.thirty], const Money.rupees(2000));
    expect(aging[AgeBucket.sixty], const Money.rupees(3000));
    expect(aging[AgeBucket.ninety], const Money.rupees(4000));
    expect(aging.total, const Money.rupees(10000));
  });

  test('the SQL and the domain agree on the boundary', () async {
    // 90 and 91 days is the difference between "chase it" and "write it off"
    // in the shopkeeper's head, and the arithmetic exists twice: once in
    // julianday and once in AgeBucket.forDays. They have to meet exactly.
    final rashid = await customer('Rashid Traders');
    await udhaar(rashid, 1000, '2026-05-25'); // exactly 90 days
    await udhaar(rashid, 2000, '2026-05-24'); // exactly 91 days

    final aging = await queries.aging(firm.firmId, asOfDateLocal: today);

    expect(daysBetween('2026-05-25', today), 90);
    expect(daysBetween('2026-05-24', today), 91);
    expect(aging[AgeBucket.sixty], const Money.rupees(1000));
    expect(aging[AgeBucket.ninety], const Money.rupees(2000));
  });

  test('a paid bill drops out of the report', () async {
    final rashid = await customer('Rashid Traders');
    final bill = await udhaar(rashid, 3000, '2026-01-05');
    await RecordReceiptUseCase(writer: DriftPaymentWriter(runner: runner)).call(
      firm.actorAt(DateTime.utc(2026, 8, 23, 9)),
      ReceiptDraft(
        partyId: rashid,
        amount: const Money.rupees(3000),
        mode: 'cash',
        paymentAccountId: (await queries.paymentAccounts(
          firm.firmId,
        )).firstWhere((a) => a.isDefault).id,
      ),
    );

    final aging = await queries.aging(firm.firmId, asOfDateLocal: today);

    expect(aging.isClear, isTrue, reason: 'bill $bill is still being aged');
  });

  test('a void bill is never aged', () async {
    final rashid = await customer('Rashid Traders');
    final voided = await udhaar(rashid, 3000, '2026-01-05');
    await runner.run(
      firm.actorAt(DateTime.utc(2026, 8, 23, 9)),
      (tx) => tx.update('documents', voided, {'status': 'void'}),
    );

    final aging = await queries.aging(firm.firmId, asOfDateLocal: today);

    expect(aging.isClear, isTrue);
  });

  group('the chase list', () {
    test('is ordered by the oldest debt, not the largest', () async {
      // A list sorted by amount puts the customer who owes Rs 40,000 since
      // last week ahead of the one who owes Rs 3,000 since March, every time.
      // They are different conversations and the second is the urgent one.
      final big = await customer('Big Recent');
      final old = await customer('Small Old');
      await udhaar(big, 40000, '2026-08-18');
      await udhaar(old, 3000, '2026-03-01');

      final chase = await queries.partiesToChase(
        firm.firmId,
        asOfDateLocal: today,
      );

      expect(chase.map((c) => c.party.name), ['Small Old', 'Big Recent']);
      expect(chase.first.oldestDays, greaterThan(170));
      expect(chase.first.bucket, AgeBucket.ninety);
    });

    test('counts how many bills are open', () async {
      // One bill from March and eleven are the same age and a different
      // conversation.
      final rashid = await customer('Rashid Traders');
      for (var i = 0; i < 3; i++) {
        await udhaar(rashid, 1000, '2026-03-0${i + 1}');
      }

      final chase = await queries.partiesToChase(
        firm.firmId,
        asOfDateLocal: today,
      );

      expect(chase.single.openBills, 3);
      expect(chase.single.party.balance, const Money.rupees(3000));
    });

    test('a customer in credit overall is not chased', () async {
      // Advance FIRST, bill after — which is how a standing-order customer
      // pays, and the only sequence that leaves an open bill alongside net
      // credit. FIFO applies a payment to whatever is open at the time, so a
      // customer who overpays an existing bill closes it and never reaches
      // this guard at all.
      //
      // The first version of this test did it the other way round and passed
      // whether the guard existed or not. Removing the guard failed nothing,
      // which is how it was found.
      final rashid = await customer('Rashid Traders');
      await RecordReceiptUseCase(
        writer: DriftPaymentWriter(runner: runner),
      ).call(
        firm.actorAt(DateTime.utc(2026, 2, 1, 9)),
        ReceiptDraft(
          partyId: rashid,
          amount: const Money.rupees(5000),
          mode: 'cash',
          paymentAccountId: (await queries.paymentAccounts(
            firm.firmId,
          )).firstWhere((a) => a.isDefault).id,
        ),
      );
      await udhaar(rashid, 3000, '2026-03-01');

      // The bill really is open, so this is not passing by having nothing to
      // look at.
      final bills = await queries.openBillsFor(firm.firmId, rashid);
      expect(bills, hasLength(1));
      expect(
        (await queries.partyById(firm.firmId, rashid))!.balance,
        const Money.rupees(-2000),
      );

      final chase = await queries.partiesToChase(
        firm.firmId,
        asOfDateLocal: today,
      );

      expect(
        chase,
        isEmpty,
        reason:
            'the shop was told to knock on the door of a customer who is '
            'Rs 2,000 in credit',
      );
    });

    test('a customer who overpaid an open bill is not chased either', () async {
      final rashid = await customer('Rashid Traders');
      await udhaar(rashid, 3000, '2026-03-01');
      await RecordReceiptUseCase(
        writer: DriftPaymentWriter(runner: runner),
      ).call(
        firm.actorAt(DateTime.utc(2026, 8, 23, 9)),
        ReceiptDraft(
          partyId: rashid,
          amount: const Money.rupees(5000),
          mode: 'cash',
          paymentAccountId: (await queries.paymentAccounts(
            firm.firmId,
          )).firstWhere((a) => a.isDefault).id,
        ),
      );

      final chase = await queries.partiesToChase(
        firm.firmId,
        asOfDateLocal: today,
      );

      expect(chase, isEmpty);
    });

    test('a shop that is owed nothing has nobody to chase', () async {
      expect(
        await queries.partiesToChase(firm.firmId, asOfDateLocal: today),
        isEmpty,
      );
    });
  });
}
