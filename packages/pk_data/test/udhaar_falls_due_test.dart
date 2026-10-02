import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// Every bill has a day it is due, and a customer's promise is kept on the
/// khata (M38) — against a real database.
///
/// The domain tests prove the arithmetic. These prove the SQL does the same
/// arithmetic on real rows: that the due date the khata shows is the one
/// `dueDateOf` would give, that a customer given longer terms has their open
/// bills move with them, that the chase list is most-late first and never
/// lists a customer the shop owes, and that a promise is kept or broken by
/// what the books say came in.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late TxRunner runner;
  late DriftAppQueries queries;
  late DriftUdhaarQueries udhaar;
  late DriftUdhaarStore store;
  late DriftCatalogueWriter catalogue;
  late PostSaleUseCase sell;
  late RecordReceiptUseCase receive;
  late String pcsUnitId;
  late String riceId;
  late String cashAccountId;

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 8, 1, 4));
    db = await openTestDatabase();
    final ids = UlidGenerator(now: clock.nowUtc);
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
    udhaar = DriftUdhaarQueries(db);
    store = DriftUdhaarStore(() => runner, ids);
    catalogue = DriftCatalogueWriter(runner);
    sell = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));
    receive = RecordReceiptUseCase(writer: DriftPaymentWriter(runner: runner));
    pcsUnitId =
        (await db.customSelect("SELECT id FROM units WHERE code = 'pcs'").get())
            .first
            .read<String>('id');
    cashAccountId = (await queries.paymentAccounts(
      firm.firmId,
    )).firstWhere((a) => a.isDefault).id;
    await runner.run(firm.actorAt(clock.nowUtc()), (tx) async {
      riceId = await tx.insert('items', {
        'name': 'Chawal Basmati',
        'name_search': 'chawal basmati',
        'base_unit_id': pcsUnitId,
        'sale_rate_milli_paisa': Rate.rupees(100).inMilliPaisa,
        'avg_cost_milli_paisa': Rate.rupees(60).inMilliPaisa,
      });
    });
  });

  tearDown(() async => db.close());

  /// The shop's actor on [day], at nine in the morning PKT.
  ActorContext on(String day) {
    final d = BusinessDate(day);
    return firm.actorAt(DateTime.utc(d.year, d.month, d.day, 4));
  }

  Future<String> customer(String name, {int? creditDays, int owed = 0}) =>
      catalogue.addParty(
        on('2026-08-01'),
        PartyDraft(
          name: name,
          creditDays: creditDays,
          openingBalance: Money.rupees(owed),
        ),
      );

  /// A bill of Rs [rupees] to [partyId] on [day], all of it on udhaar.
  Future<PostedSale> bill(String partyId, String day, int rupees) => sell(
    on(day),
    SaleDraft(
      partyId: partyId,
      lines: [
        SaleLineDraft(
          itemId: riceId,
          itemName: 'Chawal Basmati',
          qty: Qty.units(rupees ~/ 100),
          baseQty: Qty.units(rupees ~/ 100),
          unitId: pcsUnitId,
          unitCode: 'pcs',
          rate: Rate.rupees(100),
        ),
      ],
    ),
  );

  Future<RecordedReceipt> pay(String partyId, String day, int rupees) =>
      receive(
        on(day),
        ReceiptDraft(
          partyId: partyId,
          amount: Money.rupees(rupees),
          mode: 'cash',
          paymentAccountId: cashAccountId,
        ),
      );

  group('due dates', () {
    test('a bill falls due its customer credit days after its date', () async {
      final aslam = await customer('Aslam Karyana', creditDays: 15);
      await bill(aslam, '2026-08-01', 3000);

      final onTheDay = await udhaar.billsDue(
        firm.firmId,
        aslam,
        asOfDateLocal: '2026-08-16',
      );
      expect(onTheDay.single.dueDateLocal, '2026-08-16');
      expect(onTheDay.single.isDueToday, isTrue);

      final later = await udhaar.billsDue(
        firm.firmId,
        aslam,
        asOfDateLocal: '2026-08-25',
      );
      expect(later.single.daysOverdue, 9);
      expect(later.single.bucket, DueBucket.upTo30);
    });

    test('the SQL and the domain agree on every due date', () async {
      // Month ends and terms of every common length, read back through the
      // SQL and compared with the pure function the rest of the app uses.
      final days = ['2026-08-31', '2026-09-30', '2026-11-20', '2026-12-25'];
      for (final term in [null, 0, 1, 7, 15, 30, 45, 60]) {
        final id = await customer('Term $term', creditDays: term);
        for (final day in days) {
          await bill(id, day, 100);
        }
        final due = await udhaar.billsDue(
          firm.firmId,
          id,
          asOfDateLocal: '2027-01-01',
        );
        expect(
          [for (final b in due) b.dueDateLocal],
          [for (final day in days) dueDateOf(day, term)],
          reason: 'credit days $term',
        );
        for (final b in due) {
          expect(
            b.daysOverdue,
            daysBetween(b.dueDateLocal, '2027-01-01'),
            reason: 'credit days $term, bill of ${b.billDateLocal}',
          );
        }
      }
    });

    test(
      'a customer given longer terms has their open bills move with them',
      () async {
        final aslam = await customer('Aslam Karyana', creditDays: 15);
        await bill(aslam, '2026-08-01', 3000);
        final draft = await queries.partyDraft(firm.firmId, aslam);
        await catalogue.updateParty(
          on('2026-08-10'),
          aslam,
          PartyDraft(
            name: draft!.name,
            partyType: draft.partyType,
            creditDays: 30,
          ),
        );

        final due = await udhaar.billsDue(
          firm.firmId,
          aslam,
          asOfDateLocal: '2026-08-25',
        );
        expect(due.single.dueDateLocal, '2026-08-31');
        expect(due.single.isOverdue, isFalse);
      },
    );

    test('ageing by due date keeps what is not yet due apart', () async {
      final aslam = await customer('Aslam Karyana', creditDays: 15);
      final bilal = await customer('Bilal Store');
      await bill(aslam, '2026-08-01', 3000); // due 16 Aug: 30 days late
      await bill(aslam, '2026-09-10', 2000); // due 25 Sep: not yet
      await bill(bilal, '2026-05-01', 1000); // due 31 May: 108 days late

      final aging = await udhaar.dueAging(
        firm.firmId,
        asOfDateLocal: '2026-09-15',
      );
      expect(aging[DueBucket.notYetDue], const Money.rupees(2000));
      expect(aging[DueBucket.upTo30], const Money.rupees(3000));
      expect(aging[DueBucket.over90], const Money.rupees(1000));
      expect(aging.overdue, const Money.rupees(4000));
      expect(aging.total, const Money.rupees(6000));
    });

    test('the chase list is most late first, and never lists a customer '
        'the shop owes', () async {
      final recent = await customer('Big Recent', creditDays: 7);
      final old = await customer('Small Old');
      final ahead = await customer('Paid Ahead');
      await bill(recent, '2026-09-01', 40000);
      await bill(old, '2026-04-01', 3000);
      // Money on account first, a bill after: owes on the bill, in credit
      // overall. The khata says the shop owes them, and so does this.
      await pay(ahead, '2026-08-01', 5000);
      await bill(ahead, '2026-08-02', 1000);

      final list = await udhaar.dueParties(
        firm.firmId,
        asOfDateLocal: '2026-09-15',
      );
      expect([for (final p in list) p.party.name], ['Small Old', 'Big Recent']);
      expect(list.first.overdue, const Money.rupees(3000));
      expect(list.first.oldestDueLocal, '2026-05-01');
      expect(list.last.daysOverdue, 7);
      expect(list.last.party.id, recent);
      expect(old, isNot(ahead));
    });
  });

  group('promises', () {
    test('a promise is kept by a receipt inside its window', () async {
      final aslam = await customer('Aslam Karyana');
      await bill(aslam, '2026-08-01', 5000);
      final id = await store.recordPromise(
        on('2026-08-20'),
        PromiseDraft(
          partyId: aslam,
          promisedFor: '2026-08-28',
          amount: const Money.rupees(5000),
          note: 'tankhwah par',
        ),
      );
      var promise = (await udhaar.promisesOf(firm.firmId, aslam)).single;
      expect(promise.id, id);
      expect(promise.madeBy, 'Malik Sahib');
      expect(promise.note, 'tankhwah par');
      expect(promise.standingOn('2026-08-28'), PromiseStanding.dueToday);

      await pay(aslam, '2026-08-27', 5000);
      promise = (await udhaar.promisesOf(firm.firmId, aslam)).single;
      expect(promise.paidSince, const Money.rupees(5000));
      expect(promise.standingOn('2026-09-01'), PromiseStanding.kept);
    });

    test('a promise is broken when its day passes, and a new one replaces '
        'an old one', () async {
      final aslam = await customer('Aslam Karyana');
      await bill(aslam, '2026-08-01', 5000);
      await store.recordPromise(
        on('2026-08-20'),
        PromiseDraft(partyId: aslam, promisedFor: '2026-08-22'),
      );
      // Paid late: after the day, so the first is broken all the same.
      await pay(aslam, '2026-08-25', 1000);
      await store.recordPromise(
        on('2026-08-25'),
        PromiseDraft(
          partyId: aslam,
          promisedFor: '2026-09-01',
          amount: const Money.rupees(4000),
        ),
      );
      await store.recordPromise(
        on('2026-08-30'),
        PromiseDraft(partyId: aslam, promisedFor: '2026-09-05'),
      );

      final history = await udhaar.promisesOf(firm.firmId, aslam);
      expect(history, hasLength(3));
      expect(
        [for (final p in history) p.standingOn('2026-09-10')],
        [
          PromiseStanding.broken,
          PromiseStanding.replaced,
          PromiseStanding.broken,
        ],
      );
    });

    test('a promise taken off stays in the history, marked', () async {
      final aslam = await customer('Aslam Karyana');
      await bill(aslam, '2026-08-01', 5000);
      final id = await store.recordPromise(
        on('2026-08-20'),
        PromiseDraft(partyId: aslam, promisedFor: '2026-08-28'),
      );
      await store.withdrawPromise(on('2026-08-21'), id);

      final history = await udhaar.promisesOf(firm.firmId, aslam);
      expect(
        history.single.standingOn('2026-08-21'),
        PromiseStanding.withdrawn,
      );
      await expectLater(
        store.withdrawPromise(on('2026-08-21'), id),
        throwsA(isA<UdhaarRefused>()),
      );
      final audit = await db
          .customSelect(
            'SELECT action_code FROM audit_log '
            "WHERE action_code LIKE 'PROMISE_%' ORDER BY at_utc",
          )
          .get();
      expect(
        [for (final r in audit) r.read<String>('action_code')],
        ['PROMISE_RECORDED', 'PROMISE_WITHDRAWN'],
      );
    });

    test('a promise for a day gone by is refused in words', () async {
      final aslam = await customer('Aslam Karyana');
      await expectLater(
        store.recordPromise(
          on('2026-08-20'),
          PromiseDraft(partyId: aslam, promisedFor: '2026-08-19'),
        ),
        throwsA(isA<UdhaarRefused>()),
      );
      expect(await udhaar.promisesOf(firm.firmId, aslam), isEmpty);
    });

    test(
      'the morning card counts due today, overdue and promised today',
      () async {
        final aslam = await customer('Aslam Karyana', creditDays: 15);
        final bilal = await customer('Bilal Store', creditDays: 0);
        final naseem = await customer('Naseem', owed: 2500);
        await bill(aslam, '2026-08-01', 3000); // due 16 Aug
        await bill(bilal, '2026-08-01', 1200); // due 1 Aug
        await store.recordPromise(
          on('2026-08-10'),
          PromiseDraft(partyId: naseem, promisedFor: '2026-08-16'),
        );

        final today = await udhaar.udhaarToday(
          firm.firmId,
          asOfDateLocal: '2026-08-16',
        );
        expect(today.dueTodayCount, 1);
        expect(today.dueToday, const Money.rupees(3000));
        expect(today.overdueCount, 1);
        expect(today.overdue, const Money.rupees(1200));
        // Naseem owes only an opening balance, so no bill falls due, but she
        // said today, and today she is on the card at what she owes.
        expect(today.promisedTodayCount, 1);
        expect(today.promisedToday, const Money.rupees(2500));

        final list = await udhaar.dueParties(
          firm.firmId,
          asOfDateLocal: '2026-08-16',
        );
        expect(
          list
              .where((p) => p.livePromiseOn('2026-08-16') != null)
              .single
              .party
              .id,
          naseem,
        );
      },
    );
  });

  group('the khata history', () {
    test('a customer with a return has a history that ends at the khata '
        'balance', () async {
      // Found by M33's party statement: the khata's own history left out
      // goods brought back, and ran ahead of the balance above it.
      final aslam = await customer('Aslam Karyana', owed: 700);
      final sale = await bill(aslam, '2026-08-01', 3000);
      final lines = await queries.returnableLines(firm.firmId, sale.documentId);
      await RecordReturnUseCase(writer: DriftReturnWriter(runner: runner))(
        on('2026-08-03'),
        ReturnDraft(
          originalDocumentId: sale.documentId,
          lines: [
            ReturnLineDraft(
              documentLineId: lines.single.documentLineId,
              qty: Qty.units(10),
            ),
          ],
          reason: 'Keeray wala chawal',
        ),
      );
      await pay(aslam, '2026-08-05', 500);

      final party = await queries.partyById(firm.firmId, aslam);
      final history = await queries.partyLedger(firm.firmId, aslam);
      expect(party!.balance, const Money.rupees(2200));
      expect(history.last.balanceAfter, party.balance);
      final returned = history.singleWhere((e) => e.kind == 'return');
      expect(returned.amount, const Money.rupees(-1000));
    });
  });
}
