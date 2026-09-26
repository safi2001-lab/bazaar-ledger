import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// What the shop already had when it started, in the books.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late ActorContext actor;
  late TxRunner runner;
  late DriftCatalogueWriter catalogue;
  late String pcs;

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
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    catalogue = DriftCatalogueWriter(runner);
    pcs =
        (await db
                .customSelect("SELECT id FROM units WHERE code = 'pcs'")
                .getSingle())
            .read<String>('id');
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

  test('opening stock is in Inventory at what it cost', () async {
    await catalogue.addItem(
      actor,
      ItemDraft(
        name: 'Cooking Oil 5L',
        baseUnitId: pcs,
        saleRate: Rate.rupees(2500),
        openingStock: Qty.units(10),
        openingRate: Rate.rupees(2000),
      ),
    );
    expect(await net('inventory'), 2000000);
    expect(await net('opening_balances'), -2000000);
  });

  test('what a customer already owed is in Receivables', () async {
    await catalogue.addParty(
      actor,
      const PartyDraft(
        name: 'Rashid Traders',
        openingBalance: Money.rupees(4500),
      ),
    );
    expect(await net('accounts_receivable'), 450000);
    expect(await net('opening_balances'), -450000);
  });

  test('openings entered before are posted once, and only once', () async {
    await runner.run(actor, (tx) async {
      await tx.insert('parties', {
        'name': 'Old Customer',
        'name_search': 'old customer',
        'party_type': 'customer',
        'opening_balance_paisa': 300000,
      });
      final item = await tx.insert('items', {
        'name': 'Old Stock',
        'name_search': 'old stock',
        'base_unit_id': pcs,
      });
      await tx.insert('stock_ledger', {
        'item_id': item,
        'location_code': 'MAIN',
        'txn_type': 'opening',
        'qty_delta_thousandths': 5000,
        'rate_milli_paisa': 100000000,
        'value_delta_paisa': 500000,
        'balance_after_thousandths': 5000,
        'occurred_at_utc': actor.epochMillis,
        'occurred_on_local': actor.businessDate.value,
      });
    });

    expect(await runner.run(actor, postMissingOpenings), 2);
    expect(await runner.run(actor, postMissingOpenings), 0);
    expect(await net('accounts_receivable'), 300000);
    expect(await net('inventory'), 500000);
    expect(await net('opening_balances'), -800000);
  });
}
