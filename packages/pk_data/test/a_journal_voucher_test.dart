import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// Hand-written journal vouchers, against a real database.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late ActorContext actor;
  late PostJournalVoucherUseCase post;
  late DriftAppQueries queries;
  late Map<String, ChartAccount> byKey;

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 9, 26, 9, 15));
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
    post = PostJournalVoucherUseCase(
      writer: DriftJournalWriter(runner: runner),
    );
    queries = DriftAppQueries(db);
    byKey = {
      for (final a in await queries.chartOfAccounts(firm.firmId))
        if (a.systemKey != null) a.systemKey!: a,
    };
  });

  tearDown(() async => db.close());

  VoucherLine dr(String key, int rupees) => VoucherLine(
    account: byKey[key]!.asVoucherAccount,
    debit: Money.rupees(rupees),
  );
  VoucherLine cr(String key, int rupees) => VoucherLine(
    account: byKey[key]!.asVoucherAccount,
    credit: Money.rupees(rupees),
  );

  test('the owner puts money into the shop, and the chart shows it', () async {
    final no = await post(
      actor,
      narration: 'Capital brought in',
      lines: [dr('bank', 200000), cr('owner_capital', 200000)],
    );
    expect(no, startsWith('JV-'));

    final chart = {
      for (final a in await queries.chartOfAccounts(firm.firmId))
        if (a.systemKey != null) a.systemKey!: a,
    };
    expect(chart['bank']!.onItsSide, const Money.rupees(200000));
    expect(chart['owner_capital']!.onItsSide, const Money.rupees(200000));
    final ledger = await queries.accountLedger(firm.firmId, chart['bank']!.id);
    expect(ledger.single.entryNo, no);
    expect(ledger.single.balanceAfter, const Money.rupees(200000));
  });

  test('a voucher that does not balance is refused', () async {
    await expectLater(
      post(
        actor,
        narration: 'Wrong',
        lines: [dr('bank', 100), cr('owner_capital', 90)],
      ),
      throwsA(isA<VoucherRefused>()),
    );
  });

  test('a voucher cannot touch an account with a book beneath it', () async {
    await expectLater(
      post(
        actor,
        narration: 'Write down stock',
        lines: [dr('misc', 100), cr('inventory', 100)],
      ),
      throwsA(isA<VoucherRefused>()),
    );
    await expectLater(
      post(
        actor,
        narration: 'Forgive Rashid',
        lines: [dr('bad_debts', 100), cr('accounts_receivable', 100)],
      ),
      throwsA(isA<VoucherRefused>()),
    );
  });

  test('a voucher says what it is for and has two lines', () async {
    await expectLater(
      post(
        actor,
        narration: ' ',
        lines: [dr('bank', 1), cr('owner_capital', 1)],
      ),
      throwsA(isA<VoucherRefused>()),
    );
    await expectLater(
      post(actor, narration: 'One line', lines: [dr('bank', 1)]),
      throwsA(isA<VoucherRefused>()),
    );
  });
}
