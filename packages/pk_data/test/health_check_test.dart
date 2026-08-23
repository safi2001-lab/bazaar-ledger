import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// The health check has to be able to find something.
///
/// A check that only ever returns "all clear" is indistinguishable from no
/// check at all, and it is worse, because it is reassuring. Each of these
/// plants a specific kind of damage — the kinds that keep the books balanced
/// while the numbers stop being true — and requires the check to name it.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = await openTestDatabase();
  });

  tearDown(() => db.close());

  test('a clean database is reported clean', () async {
    final health = await db.checkHealth();
    expect(health.isHealthy, isTrue, reason: health.toString());
  });

  test('an over-allocated payment is found', () async {
    // Rs 500 received, Rs 800 of it allocated across two bills. Every table
    // still satisfies every CHECK, the journal still balances, and two
    // customers' khatas are both wrong.
    await _seedShop(db);
    await db.customStatement(
      'UPDATE payment_allocations SET amount_paisa = amount_paisa + 30000 '
      'WHERE id = (SELECT id FROM payment_allocations LIMIT 1)',
    );

    final findings = await db.findOverAllocatedPayments();
    expect(findings, hasLength(1));
    expect(findings.single, contains('allocated'));

    final health = await db.checkHealth();
    expect(health.isHealthy, isFalse);
  });

  test('a stock balance that has drifted from its ledger is found', () async {
    await _seedShop(db);
    await db.customStatement(
      'UPDATE stock_ledger SET balance_after_thousandths = 999999 '
      'WHERE id = (SELECT id FROM stock_ledger LIMIT 1)',
    );

    final findings = await db.findStockLedgerDrift();
    expect(findings, hasLength(1));
    expect(findings.single, contains('999999'));

    final health = await db.checkHealth();
    expect(health.isHealthy, isFalse);
  });

  test('an unbalanced journal entry is found', () async {
    await _seedShop(db);
    await db.customStatement(
      'UPDATE journal_lines SET debit_paisa = debit_paisa + 1 '
      'WHERE id = (SELECT id FROM journal_lines WHERE debit_paisa > 0 LIMIT 1)',
    );

    final health = await db.checkHealth();
    expect(health.isHealthy, isFalse);
    expect(
      health.findings.join(' '),
      contains('out by 1'),
      reason: 'one paisa is enough; there is no tolerance anywhere',
    );
  });
}

/// A shop with one sale in it, written through the real path.
Future<void> _seedShop(AppDatabase db) async {
  final ids = UlidGenerator();
  const clock = SystemClock();
  final run = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
    shopName: 'Chishti Kiryana Store',
    ownerName: 'Malik Sahib',
    deviceLabel: 'Counter 1',
    platform: 'test',
  );

  final hlc = await resumeHlcClock(db, deviceId: run.deviceId, clock: clock);
  final runner = TxRunner(database: db, ids: ids, hlc: hlc);
  final actor = ActorContext(
    firmId: run.firmId,
    userId: run.ownerUserId,
    deviceId: run.deviceId,
    startedAtUtc: clock.nowUtc(),
  );

  final units = await DriftAppQueries(db).units(run.firmId);
  final pcs = units.firstWhere((u) => u.code == 'pcs');
  final itemId = await DriftCatalogueWriter(runner).addItem(
    actor,
    ItemDraft(
      name: 'Cooking Oil 5L',
      baseUnitId: pcs.id,
      saleRate: const Rate.rupees(500),
      openingStock: const Qty.units(20),
      openingRate: const Rate.rupees(300),
    ),
  );

  final accounts = await DriftAppQueries(db).paymentAccounts(run.firmId);
  await PostSaleUseCase(writer: DriftSaleWriter(runner: runner)).call(
    actor,
    SaleDraft(
      lines: [
        SaleLineDraft(
          itemId: itemId,
          itemName: 'Cooking Oil 5L',
          qty: Qty.one,
          baseQty: Qty.one,
          unitCode: 'pcs',
          rate: const Rate.rupees(500),
        ),
      ],
      tenders: [
        TenderDraft(
          paymentAccountId: accounts.single.id,
          mode: 'cash',
          amount: const Money.rupees(500),
        ),
      ],
      roundToRupee: false,
    ),
  );
}
