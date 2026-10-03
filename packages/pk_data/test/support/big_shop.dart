import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';

import 'large_catalogue.dart';

/// Three years of a wholesaler, seeded the fast way (M62).
///
/// Rupin is "unusable at about 180 customers"; Vyapar's reviews are full of
/// "Loading… Loading…". The shop this product is built for is the
/// wholesaler with years of bills, and the numbers here are his: fifty
/// thousand bills of five lines each over three fiscal years (a quarter of
/// a million lines), two thousand parties, five thousand items, twenty
/// thousand receipts on the khatas and three thousand deliveries — with
/// their payments, their journal entries and their stock movements, so the
/// lists and the reports read rows of the shape and size the app writes.
///
/// Like M33's and M34's fixtures this goes around `TxRunner` (one statement
/// per table, `INSERT ... SELECT` over a counter): what is measured is the
/// read. And it is shaped the way a real book is, not uniformly:
///
/// * one bill in ten is a walk-in, with no party;
/// * a quarter of the rest go to twenty big customers — about 560 bills
///   each over the three years, the regulars who make a wholesaler's khata
///   long — and the rest across 1,930 others, in twelve routes with a few
///   left ungrouped;
/// * a third of the named bills are udhaar. Every udhaar bill has a receipt
///   for half of it a week later, cash or JazzCash; the oldest third of them
///   a second receipt by JazzCash a month on that settles it; the rest are
///   still half owed, which is the chase list;
/// * one counter bill in ten is paid part in cash and part by JazzCash.
///
/// Every id sorts in the order things happened, as a ULID does, because the
/// sales list pages on the id.
final class BigShop {
  const BigShop({
    required this.firm,
    required this.bigCustomer,
    required this.bigCustomerName,
    required this.bills,
    required this.receipts,
  });

  final FirstRunResult firm;

  /// One of the twenty regulars: hundreds of bills and receipts.
  final String bigCustomer;
  final String bigCustomerName;
  final int bills;
  final int receipts;

  /// The day the fixture ends, and the tests' "today".
  static const today = BusinessDate('2026-06-30');
}

const bigShopBills = 50000;
const bigShopParties = 2000;
const bigShopSuppliers = 50;
const bigShopItems = 5000;
const bigShopReceipts = 20000;
const bigShopPurchases = 3000;

/// The two halves of a name the khata is searched by.
const _firstNames = [
  'Rashid',
  'Bilal',
  'Akbar',
  'Imran',
  'Haji Aslam',
  'Madina',
  'Al-Falah',
  'Chaudhry',
  'Sheikh',
  'Butt',
  'Malik',
  'Qureshi',
  'Ansari',
  'Rehman',
  'Usman',
  'Zubair',
  'Noor',
  'Data',
  'Ghousia',
  'Bismillah',
];
const _kinds = [
  'Traders',
  'General Store',
  'Kiryana',
  'Brothers',
  'and Sons',
  'Wholesale',
  'Mart',
  'Store',
];

String bigShopPartyName(int i) =>
    '${_firstNames[i % _firstNames.length]} '
    '${_kinds[(i ~/ _firstNames.length) % _kinds.length]} $i';

Future<BigShop> seedBigShop(AppDatabase db) async {
  final clock = FixedClock(DateTime.utc(2026, 6, 30, 9));
  final ids = UlidGenerator(now: clock.nowUtc);
  final firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
    shopName: 'Chishti Wholesale',
    ownerName: 'Malik Sahib',
    deviceLabel: 'Counter 1',
    platform: 'test',
    city: 'Lahore',
  );

  Future<String> idOf(String sql) async =>
      (await db.customSelect(sql).getSingle()).read<String>('id');
  final pcs = await idOf("SELECT id FROM units WHERE code = 'pcs'");
  String account(String key) =>
      "(SELECT id FROM accounts WHERE system_key = '$key')";
  final cashDrawer = await idOf(
    "SELECT id FROM payment_accounts WHERE mode_label = 'cash'",
  );
  final jazzWallet = await idOf(
    "SELECT id FROM payment_accounts WHERE mode_label = 'jazzcash'",
  );
  final walletLedger = await idOf(
    'SELECT ledger_account_id AS id FROM payment_accounts '
    "WHERE mode_label = 'jazzcash'",
  );

  await seedLargeCatalogue(
    db,
    firmId: firm.firmId,
    userId: firm.ownerUserId,
    deviceId: firm.deviceId,
    baseUnitId: pcs,
    items: bigShopItems,
  );

  final audit = [
    firm.firmId,
    firm.ownerUserId,
    firm.ownerUserId,
    firm.deviceId,
  ];
  const columns =
      'id, firm_id, created_at_utc, updated_at_utc, created_by, updated_by, '
      'origin_device_id, hlc';
  // The milliseconds of a business day's morning, plus a few for order.
  String millisOf(String day, String plus) =>
      'CAST((julianday($day) - 2440587.5) * 86400000 AS INTEGER) + $plus';
  const fiscalYear =
      "CASE WHEN day < '2024-07-01' THEN 2324 "
      "WHEN day < '2025-07-01' THEN 2425 ELSE 2526 END";

  await db.transaction(() async {
    // --- Parties: 1,950 customers and 50 suppliers -----------------------
    for (var i = 0; i < bigShopParties; i++) {
      final supplier = i >= bigShopParties - bigShopSuppliers;
      final name = supplier ? 'Supplier Mills $i' : bigShopPartyName(i);
      await db.customStatement(
        '''
        INSERT INTO parties ($columns, name, name_search, party_type, phone,
                             party_group)
        VALUES (?, ?, 0, 0, ?, ?, ?, 'h', ?, ?, ?, ?, ?)
        ''',
        [
          'bp-${i.toString().padLeft(4, '0')}',
          ...audit,
          name,
          nameSearchColumn(name),
          supplier ? 'supplier' : 'customer',
          '03${i % 10}${(1000000 + i * 37).toString().padLeft(8, '0')}',
          supplier || i % 10 >= 7 ? null : 'Route ${i % 12 + 1}',
        ],
      );
    }

    // --- The bills' shape, in scratch tables ------------------------------
    await db.customStatement('''
      CREATE TEMP TABLE bs_line AS
      WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n
                              WHERE i < $bigShopBills - 1),
           k(k) AS (VALUES (1), (2), (3), (4), (5))
      SELECT i, k,
             printf('itm%08d', (i * 7 + k * 1013) % $bigShopItems) AS item,
             1 + (i + k) % 5 AS qty,
             (100 + (i * 13 + k * 7) % 400) * 100 AS rate
      FROM n, k
      ''');
    await db.customStatement('''
      CREATE TEMP TABLE bs_bill AS
      SELECT i,
             CASE WHEN i % 10 = 9 THEN NULL
                  WHEN i % 4 = 0 THEN printf('bp-%04d', (i / 4) % 20)
                  ELSE printf('bp-%04d', 20 + i % 1930) END AS party,
             date('2023-07-01', '+' || (i * 1096 / $bigShopBills) || ' days')
               AS day,
             SUM(qty * rate) AS total,
             SUM(qty * rate * 8 / 10) AS cost
      FROM bs_line GROUP BY i
      ''');
    await db.customStatement('''
      CREATE TEMP TABLE bs_kind AS
      SELECT i, CASE WHEN party IS NOT NULL AND i % 3 = 0 THEN 2
                     WHEN i % 10 = 1 THEN 1 ELSE 0 END AS kind
      FROM bs_bill
      ''');
    await db.customStatement('''
      CREATE TEMP TABLE bs_udhaar AS
      SELECT ROW_NUMBER() OVER (ORDER BY b.i) - 1 AS k, b.i AS i
      FROM bs_bill b JOIN bs_kind USING (i) WHERE kind = 2
      ''');
    // Every udhaar bill a receipt for half a week on; the oldest of them a
    // second, for the rest, a month on — twenty thousand in all.
    await db.customStatement('''
      CREATE TEMP TABLE bs_receipt AS
      WITH RECURSIVE r(r) AS (SELECT 0 UNION ALL SELECT r + 1 FROM r
                              WHERE r < $bigShopReceipts - 1),
           u(n) AS (SELECT COUNT(*) FROM bs_udhaar)
      SELECT r.r AS r, b.i AS i, b.party AS party, r.r / u.n AS part,
             CASE WHEN r.r / u.n = 0 THEN b.total / 2
                  ELSE b.total - b.total / 2 END AS amount,
             MIN(date(b.day, CASE WHEN r.r / u.n = 0 THEN '+7 days'
                                  ELSE '+30 days' END), '2026-06-30') AS day,
             CASE WHEN r.r / u.n = 0 AND r.r % 2 = 0 THEN 'cash'
                  ELSE 'jazzcash' END AS mode
      FROM r, u
      JOIN bs_udhaar x ON x.k = r.r % u.n
      JOIN bs_bill b ON b.i = x.i
      ''');

    // --- Sale bills and their lines ---------------------------------------
    await db.customStatement('''
      INSERT INTO documents ($columns, doc_type, doc_no, doc_series, doc_seq,
                             fiscal_year, doc_date_utc, doc_date_local,
                             party_id, party_name_snapshot, status,
                             posted_at_utc, subtotal_paisa, taxable_paisa,
                             total_paisa, paid_paisa, balance_paisa,
                             cost_paisa)
      SELECT printf('bd-%07d', b.i), ?, ${millisOf('b.day', 'b.i')},
             ${millisOf('b.day', 'b.i')}, ?, ?, ?, 'h',
             'sale_invoice', printf('INV-%07d', b.i), 'INV', b.i + 1,
             ${fiscalYear.replaceAll('day', 'b.day')},
             ${millisOf('b.day', 'b.i')}, b.day, b.party,
             (SELECT name FROM parties WHERE id = b.party), 'posted',
             ${millisOf('b.day', 'b.i')}, b.total, b.total, b.total,
             b.total - CASE WHEN kind = 2 THEN b.total - COALESCE((
               SELECT SUM(amount) FROM bs_receipt r WHERE r.i = b.i), 0)
               ELSE 0 END,
             CASE WHEN kind = 2 THEN b.total - COALESCE((
               SELECT SUM(amount) FROM bs_receipt r WHERE r.i = b.i), 0)
               ELSE 0 END,
             b.cost
      FROM bs_bill b JOIN bs_kind USING (i)
      ''', audit);
    await db.customStatement(
      '''
      INSERT INTO document_lines ($columns, document_id, line_no, item_id,
                                  item_name_snapshot, qty_thousandths,
                                  unit_id, unit_code_snapshot,
                                  base_qty_thousandths, rate_milli_paisa,
                                  gross_paisa, taxable_paisa,
                                  line_total_paisa, cost_paisa)
      SELECT printf('bl-%07d-%d', l.i, l.k), ?, ${millisOf('b.day', 'l.i')},
             ${millisOf('b.day', 'l.i')}, ?, ?, ?, 'h',
             printf('bd-%07d', l.i), l.k, l.item,
             (SELECT name FROM items WHERE id = l.item), l.qty * 1000, ?,
             'pcs', l.qty * 1000, l.rate * 1000, l.qty * l.rate,
             l.qty * l.rate, l.qty * l.rate, l.qty * l.rate * 8 / 10
      FROM bs_line l JOIN bs_bill b ON b.i = l.i
      ''',
      [...audit, pcs],
    );
    await db.customStatement('''
      INSERT INTO stock_ledger ($columns, item_id, location_code, document_id,
                                document_line_id, txn_type,
                                qty_delta_thousandths, rate_milli_paisa,
                                value_delta_paisa, occurred_at_utc,
                                occurred_on_local)
      SELECT printf('bsl-%07d-%d', l.i, l.k), ?, ${millisOf('b.day', 'l.i')},
             ${millisOf('b.day', 'l.i')}, ?, ?, ?, 'h',
             l.item, 'MAIN', printf('bd-%07d', l.i),
             printf('bl-%07d-%d', l.i, l.k), 'sale', -l.qty * 1000,
             l.rate * 800, -(l.qty * l.rate * 8 / 10),
             ${millisOf('b.day', 'l.i')}, b.day
      FROM bs_line l JOIN bs_bill b ON b.i = l.i
      ''', audit);

    // --- What was paid at the counter: cash, or cash and JazzCash ---------
    for (final (tag, mode, wallet, amount, which) in [
      ('c', 'cash', cashDrawer, 'b.total', 'kind = 0'),
      ('c', 'cash', cashDrawer, 'b.total * 6 / 10', 'kind = 1'),
      ('j', 'jazzcash', jazzWallet, 'b.total - b.total * 6 / 10', 'kind = 1'),
    ]) {
      await db.customStatement(
        '''
        INSERT INTO payments ($columns, payment_no, direction, party_id,
                              payment_account_id, mode, amount_paisa,
                              payment_date_utc, payment_date_local, status)
        SELECT printf('bpay-$tag-%07d', b.i), ?,
               ${millisOf('b.day', 'b.i')}, ${millisOf('b.day', 'b.i')},
               ?, ?, ?, 'h',
               printf('P$tag-%07d', b.i), 'in', b.party, ?, '$mode', $amount,
               ${millisOf('b.day', 'b.i')}, b.day, 'cleared'
        FROM bs_bill b JOIN bs_kind USING (i) WHERE $which
        ''',
        [...audit, wallet],
      );
      await db.customStatement('''
        INSERT INTO payment_allocations ($columns, payment_id, document_id,
                                         amount_paisa, allocation_mode,
                                         allocated_at_utc)
        SELECT printf('bal-$tag-%07d', b.i), ?,
               ${millisOf('b.day', 'b.i')}, ${millisOf('b.day', 'b.i')},
               ?, ?, ?, 'h',
               printf('bpay-$tag-%07d', b.i), printf('bd-%07d', b.i),
               $amount, 'exact', ${millisOf('b.day', 'b.i')}
        FROM bs_bill b JOIN bs_kind USING (i) WHERE $which
        ''', audit);
    }

    // --- Receipts on the khatas -------------------------------------------
    await db.customStatement(
      '''
      INSERT INTO payments ($columns, payment_no, direction, party_id,
                            payment_account_id, mode, amount_paisa,
                            payment_date_utc, payment_date_local, status)
      SELECT printf('brcv-%05d', r.r), ?, ${millisOf('r.day', '50000 + r.r')},
             ${millisOf('r.day', '50000 + r.r')}, ?, ?, ?, 'h',
             printf('RCV-%05d', r.r), 'in', r.party,
             CASE r.mode WHEN 'cash' THEN ? ELSE ? END, r.mode, r.amount,
             ${millisOf('r.day', '50000 + r.r')}, r.day, 'cleared'
      FROM bs_receipt r
      ''',
      [...audit, cashDrawer, jazzWallet],
    );
    await db.customStatement('''
      INSERT INTO payment_allocations ($columns, payment_id, document_id,
                                       amount_paisa, allocation_mode,
                                       allocated_at_utc)
      SELECT printf('bra-%05d', r.r), ?, ${millisOf('r.day', '50000 + r.r')},
             ${millisOf('r.day', '50000 + r.r')}, ?, ?, ?, 'h',
             printf('brcv-%05d', r.r), printf('bd-%07d', r.i), r.amount,
             'fifo', ${millisOf('r.day', '50000 + r.r')}
      FROM bs_receipt r
      ''', audit);

    // --- The books: an entry for every bill and every receipt -------------
    await db.customStatement('''
      INSERT INTO journal_entries ($columns, entry_no, entry_date_utc,
                                   entry_date_local, fiscal_year, source_type,
                                   document_id, narration, total_debit_paisa,
                                   total_credit_paisa)
      SELECT printf('bje-%07d', b.i), ?, ${millisOf('b.day', 'b.i')},
             ${millisOf('b.day', 'b.i')}, ?, ?, ?, 'h',
             printf('JV-S-%07d', b.i), ${millisOf('b.day', 'b.i')}, b.day,
             ${fiscalYear.replaceAll('day', 'b.day')}, 'sale',
             printf('bd-%07d', b.i), 'Sale ' || printf('INV-%07d', b.i),
             b.total, b.total
      FROM bs_bill b
      ''', audit);
    for (final (no, debitAccount, amount, party, which) in [
      (1, account('cash_in_hand'), 'b.total', 'NULL', 'kind = 0'),
      (1, account('cash_in_hand'), 'b.total * 6 / 10', 'NULL', 'kind = 1'),
      (2, "'$walletLedger'", 'b.total - b.total * 6 / 10', 'NULL', 'kind = 1'),
      (3, account('accounts_receivable'), 'b.total', 'b.party', 'kind = 2'),
    ]) {
      await db.customStatement('''
        INSERT INTO journal_lines ($columns, journal_entry_id, line_no,
                                   account_id, debit_paisa, party_id)
        SELECT printf('bjl-%07d-$no', b.i), ?, ${millisOf('b.day', 'b.i')},
               ${millisOf('b.day', 'b.i')}, ?, ?, ?, 'h',
               printf('bje-%07d', b.i), $no, $debitAccount, $amount, $party
        FROM bs_bill b JOIN bs_kind USING (i) WHERE $which
        ''', audit);
    }
    await db.customStatement('''
      INSERT INTO journal_lines ($columns, journal_entry_id, line_no,
                                 account_id, credit_paisa)
      SELECT printf('bjl-%07d-4', b.i), ?, ${millisOf('b.day', 'b.i')},
             ${millisOf('b.day', 'b.i')}, ?, ?, ?, 'h',
             printf('bje-%07d', b.i), 4, ${account('sales')}, b.total
      FROM bs_bill b
      ''', audit);
    await db.customStatement('''
      INSERT INTO journal_entries ($columns, entry_no, entry_date_utc,
                                   entry_date_local, fiscal_year, source_type,
                                   payment_id, narration, total_debit_paisa,
                                   total_credit_paisa)
      SELECT printf('bjr-%05d', r.r), ?, ${millisOf('r.day', '50000 + r.r')},
             ${millisOf('r.day', '50000 + r.r')}, ?, ?, ?, 'h',
             printf('JV-R-%05d', r.r), ${millisOf('r.day', '50000 + r.r')},
             r.day, ${fiscalYear.replaceAll('day', 'r.day')}, 'payment',
             printf('brcv-%05d', r.r), 'Receipt ' || printf('RCV-%05d', r.r),
             r.amount, r.amount
      FROM bs_receipt r
      ''', audit);
    await db.customStatement('''
      INSERT INTO journal_lines ($columns, journal_entry_id, line_no,
                                 account_id, debit_paisa)
      SELECT printf('bjrl-%05d-1', r.r), ?, ${millisOf('r.day', '50000 + r.r')},
             ${millisOf('r.day', '50000 + r.r')}, ?, ?, ?, 'h',
             printf('bjr-%05d', r.r), 1,
             CASE r.mode WHEN 'cash' THEN ${account('cash_in_hand')}
                  ELSE '$walletLedger' END, r.amount
      FROM bs_receipt r
      ''', audit);
    await db.customStatement('''
      INSERT INTO journal_lines ($columns, journal_entry_id, line_no,
                                 account_id, credit_paisa, party_id)
      SELECT printf('bjrl-%05d-2', r.r), ?, ${millisOf('r.day', '50000 + r.r')},
             ${millisOf('r.day', '50000 + r.r')}, ?, ?, ?, 'h',
             printf('bjr-%05d', r.r), 2, ${account('accounts_receivable')},
             r.amount, r.party
      FROM bs_receipt r
      ''', audit);

    // --- Deliveries from the fifty suppliers, left owing ------------------
    await db.customStatement('''
      CREATE TEMP TABLE bs_buy AS
      WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n
                              WHERE i < $bigShopPurchases - 1),
           k(k) AS (VALUES (1), (2), (3), (4), (5))
      SELECT i, k,
             -- A quarter of the deliveries from one mill, the shop's
             -- main supplier, whose account is long.
             CASE WHEN i % 4 = 0
                  THEN printf('bp-%04d', ${bigShopParties - bigShopSuppliers})
                  ELSE printf('bp-%04d', ${bigShopParties - bigShopSuppliers}
                              + i % $bigShopSuppliers) END AS party,
             date('2023-07-01', '+' || (i * 1096 / $bigShopPurchases)
                  || ' days') AS day,
             printf('itm%08d', (i * 11 + k * 997) % $bigShopItems) AS item,
             (20 + (i + k) % 80) AS qty,
             (80 + (i * 17 + k) % 300) * 100 AS rate
      FROM n, k
      ''');
    await db.customStatement('''
      INSERT INTO documents ($columns, doc_type, doc_no, doc_series, doc_seq,
                             fiscal_year, doc_date_utc, doc_date_local,
                             party_id, status, posted_at_utc, subtotal_paisa,
                             total_paisa, balance_paisa)
      SELECT printf('bpd-%05d', i), ?, ${millisOf('day', 'i')},
             ${millisOf('day', 'i')}, ?, ?, ?, 'h', 'purchase_bill',
             printf('PUR-%05d', i), 'PUR', i + 1, $fiscalYear,
             ${millisOf('day', 'i')}, day, party, 'posted',
             ${millisOf('day', 'i')}, SUM(qty * rate), SUM(qty * rate),
             SUM(qty * rate)
      FROM bs_buy GROUP BY i
      ''', audit);
    await db.customStatement(
      '''
      INSERT INTO document_lines ($columns, document_id, line_no, item_id,
                                  item_name_snapshot, qty_thousandths,
                                  unit_id, unit_code_snapshot,
                                  base_qty_thousandths, rate_milli_paisa,
                                  gross_paisa, line_total_paisa, cost_paisa)
      SELECT printf('bpl-%05d-%d', i, k), ?, ${millisOf('day', 'i')},
             ${millisOf('day', 'i')}, ?, ?, ?, 'h', printf('bpd-%05d', i), k,
             item, (SELECT name FROM items WHERE id = item), qty * 1000, ?,
             'pcs', qty * 1000, rate * 1000, qty * rate, qty * rate,
             qty * rate
      FROM bs_buy
      ''',
      [...audit, pcs],
    );
    await db.customStatement('''
      INSERT INTO stock_ledger ($columns, item_id, location_code, document_id,
                                document_line_id, txn_type,
                                qty_delta_thousandths, rate_milli_paisa,
                                value_delta_paisa, occurred_at_utc,
                                occurred_on_local)
      SELECT printf('bps-%05d-%d', i, k), ?, ${millisOf('day', 'i')},
             ${millisOf('day', 'i')}, ?, ?, ?, 'h', item, 'MAIN',
             printf('bpd-%05d', i), printf('bpl-%05d-%d', i, k), 'purchase',
             qty * 1000, rate * 1000, qty * rate, ${millisOf('day', 'i')}, day
      FROM bs_buy
      ''', audit);
    await db.customStatement('''
      INSERT INTO journal_entries ($columns, entry_no, entry_date_utc,
                                   entry_date_local, fiscal_year, source_type,
                                   document_id, narration, total_debit_paisa,
                                   total_credit_paisa)
      SELECT printf('bjp-%05d', i), ?, ${millisOf('day', 'i')},
             ${millisOf('day', 'i')}, ?, ?, ?, 'h', printf('JV-P-%05d', i),
             ${millisOf('day', 'i')}, day, $fiscalYear, 'purchase',
             printf('bpd-%05d', i), 'Purchase ' || printf('PUR-%05d', i),
             SUM(qty * rate), SUM(qty * rate)
      FROM bs_buy GROUP BY i
      ''', audit);
    for (final (no, column, key, party) in [
      (1, 'debit_paisa', 'inventory', 'NULL'),
      (2, 'credit_paisa', 'accounts_payable', 'party'),
    ]) {
      await db.customStatement('''
        INSERT INTO journal_lines ($columns, journal_entry_id, line_no,
                                   account_id, $column, party_id)
        SELECT printf('bjpl-%05d-$no', i), ?, ${millisOf('day', 'i')},
               ${millisOf('day', 'i')}, ?, ?, ?, 'h', printf('bjp-%05d', i),
               $no, ${account(key)}, SUM(qty * rate), $party
        FROM bs_buy GROUP BY i
        ''', audit);
    }

    for (final scratch in [
      'bs_line',
      'bs_bill',
      'bs_kind',
      'bs_udhaar',
      'bs_receipt',
      'bs_buy',
    ]) {
      await db.customStatement('DROP TABLE $scratch');
    }
  });
  // Planned against the real sizes, as the phone's own ANALYZE would.
  await db.customStatement('ANALYZE');

  final counts = await db.customSelect('''
      SELECT (SELECT COUNT(*) FROM documents
               WHERE doc_type = 'sale_invoice') AS bills,
             (SELECT COUNT(*) FROM payments
               WHERE payment_no LIKE 'RCV-%') AS receipts
      ''').getSingle();
  return BigShop(
    firm: firm,
    bigCustomer: 'bp-0007',
    bigCustomerName: bigShopPartyName(7),
    bills: counts.read<int>('bills'),
    receipts: counts.read<int>('receipts'),
  );
}

/// The best of three timings of [work], in milliseconds.
///
/// The suite runs its files side by side, and other work shares the
/// machine; one timing measures the neighbours as much as the query. The
/// best of three is the query's own cost.
Future<int> bestOfThreeMillis(Future<void> Function() work) async {
  var best = 1 << 30;
  for (var run = 0; run < 3; run++) {
    final ms = await millisFor(work);
    if (ms < best) best = ms;
  }
  return best;
}
