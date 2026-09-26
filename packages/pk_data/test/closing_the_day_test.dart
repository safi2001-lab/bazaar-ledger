import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// Counting the drawer at the end of the day, against a real database.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late ActorContext actor;
  late CloseDayUseCase close;

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 9, 26, 17));
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
    final runner = TxRunner(database: db, ids: ids, hlc: hlc);
    close = CloseDayUseCase(writer: DriftDayCloseWriter(runner: runner));

    // Rs 5,000 of cash sales today, through the cash tender's account.
    final cash = (await DriftAppQueries(
      db,
    ).paymentAccounts(firm.firmId)).firstWhere((a) => a.modeLabel == 'cash');
    final pcs =
        (await db
                .customSelect("SELECT id FROM units WHERE code = 'pcs'")
                .getSingle())
            .read<String>('id');
    late String sugar;
    await runner.run(actor, (tx) async {
      sugar = await tx.insert('items', {
        'name': 'Sugar 1kg',
        'name_search': 'sugar 1kg',
        'base_unit_id': pcs,
        'track_stock': 0,
      });
    });
    await PostSaleUseCase(writer: DriftSaleWriter(runner: runner))(
      actor,
      SaleDraft(
        lines: [
          SaleLineDraft(
            itemId: sugar,
            itemName: 'Sugar 1kg',
            qty: Qty.units(1),
            baseQty: Qty.units(1),
            unitCode: 'pcs',
            rate: Rate.rupees(5000),
            tracksStock: false,
          ),
        ],
        tenders: [
          TenderDraft(
            paymentAccountId: cash.id,
            mode: 'cash',
            amount: const Money.rupees(5000),
          ),
        ],
      ),
    );
  });

  tearDown(() async => db.close());

  Future<int> net(String systemKey) async =>
      (await db
              .customSelect(
                'SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) '
                'AS n FROM journal_lines jl '
                'JOIN accounts a ON a.id = jl.account_id '
                "WHERE a.system_key = '$systemKey'",
              )
              .getSingle())
          .read<int>('n');

  Future<List<Map<String, Object?>>> closes() async => [
    for (final r
        in await db
            .customSelect(
              'SELECT summary, created_by FROM audit_log '
              "WHERE action_code = 'DAY_CLOSED' ORDER BY at_utc, rowid",
            )
            .get())
      r.data,
  ];

  test(
    'a drawer that matches the books writes nothing but the close',
    () async {
      final closed = await close(actor, counted: const Money.rupees(5000));

      expect(closed.expected, const Money.rupees(5000));
      expect(closed.journal, isNull);
      expect(await net('cash_short_over'), 0);
      expect((await closes()).single['summary'], contains('matched the books'));
    },
  );

  test(
    'a short drawer is booked as a shortage, and the books then agree',
    () async {
      final closed = await close(
        actor,
        counted: const Money.rupees(4800),
        note: 'Change given twice',
      );

      expect(closed.shortBy, const Money.rupees(200));
      expect(await net('cash_short_over'), 20000);
      final cashNow = await close(actor, counted: const Money.rupees(4800));
      expect(cashNow.expected, const Money.rupees(4800));
      expect(
        (await closes()).first['summary'],
        contains('short by 200.00: Change given twice'),
      );
      expect((await closes()).first['created_by'], firm.ownerUserId);
    },
  );

  test('a drawer over the books is booked the other way', () async {
    await close(actor, counted: const Money.rupees(5100));
    expect(await net('cash_short_over'), -10000);
  });

  test('a drawer cannot be counted below nothing', () async {
    await expectLater(
      close(actor, counted: const Money.rupees(-1)),
      throwsA(isA<DayCloseRefused>()),
    );
  });

  test('the activity log names who did what, newest first', () async {
    await close(actor, counted: const Money.rupees(4800));
    final queries = DriftAppQueries(db);

    final log = await queries.activity(firm.firmId);
    expect(log.first.actionCode, 'DAY_CLOSED');
    expect(log.first.userName, 'Malik Sahib');
    expect(log.map((e) => e.actionCode), contains('SALE_POSTED'));
    final mine = await queries.activity(firm.firmId, userId: firm.ownerUserId);
    expect(mine, hasLength(log.length));
    expect(await queries.activity(firm.firmId, userId: 'nobody'), isEmpty);
    expect(
      (await queries.lastDayClose(firm.firmId))!.summary,
      contains('short'),
    );
    expect(await queries.cashInDrawer(firm.firmId), const Money.rupees(4800));
  });
}
