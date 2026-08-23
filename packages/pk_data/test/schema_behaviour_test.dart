import 'package:pk_data/pk_data.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// `ddl_invariants_test` proves the constraints are declared.
/// This proves they bite.
///
/// A CHECK nobody has ever seen fail is indistinguishable from a comment.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = await openTestDatabase();
    await _seedFirstRun(db);
  });

  tearDown(() async => db.close());

  test(
    'first run seeds a firm, a device and an owner with foreign keys on',
    () async {
      final firms = await db.customSelect('SELECT * FROM firms').get();
      expect(firms, hasLength(1));
      expect(firms.single.read<String>('name'), 'Chishti Kiryana Store');
      // The firm scopes itself. This is what lets every other table declare a
      // real foreign key to firms(id) with no cycle anywhere in the schema.
      expect(
        firms.single.read<String>('firm_id'),
        firms.single.read<String>('id'),
      );

      final orphans = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(orphans, isEmpty);
    },
  );

  test('a firm whose firm_id is not its own id is rejected', () {
    expect(
      db.customStatement('''
        INSERT INTO firms ($_env, name)
        VALUES ('F2', 'F1', 1, 1, 'U1', 'U1', NULL, 'D1', 'h', 1, 'Fake')
      '''),
      _throwsSqlite('CHECK constraint failed'),
    );
  });

  test('a document referencing a party that does not exist is rejected', () {
    // The single most valuable thing foreign keys do here: an invoice can
    // never point at a customer who is not in the khata.
    expect(
      db.customStatement('''
        INSERT INTO documents ($_env, doc_type, doc_no, doc_series, doc_seq,
          fiscal_year, doc_date_utc, doc_date_local, party_id)
        VALUES ('X1', 'F1', 1, 1, 'U1', 'U1', NULL, 'D1', 'h', 1,
          'sale_invoice', 'INV-2627-0001', 'INV', 1, 2627, 1, '2026-08-23',
          'no-such-party')
      '''),
      _throwsSqlite('FOREIGN KEY constraint failed'),
    );
  });

  test('a STRICT table refuses text in an integer column', () {
    // Without STRICT this insert succeeds and `total_paisa` silently holds the
    // string 'abc'. Every sum over that column then returns a wrong number
    // with no error anywhere.
    expect(
      db.customStatement('''
        INSERT INTO documents ($_env, doc_type, doc_no, doc_series, doc_seq,
          fiscal_year, doc_date_utc, doc_date_local, total_paisa)
        VALUES ('X2', 'F1', 1, 1, 'U1', 'U1', NULL, 'D1', 'h', 1,
          'sale_invoice', 'INV-2627-0002', 'INV', 2, 2627, 1, '2026-08-23',
          'abc')
      '''),
      _throwsSqlite('cannot store TEXT value in INTEGER column'),
    );
  });

  test(
    'the same invoice number cannot be issued twice in one firm and year',
    () async {
      await db.customStatement('''
      INSERT INTO documents ($_env, doc_type, doc_no, doc_series, doc_seq,
        fiscal_year, doc_date_utc, doc_date_local)
      VALUES ('X3', 'F1', 1, 1, 'U1', 'U1', NULL, 'D1', 'h', 1,
        'sale_invoice', 'INV-2627-0003', 'INV', 3, 2627, 1, '2026-08-23')
    ''');
      expect(
        db.customStatement('''
        INSERT INTO documents ($_env, doc_type, doc_no, doc_series, doc_seq,
          fiscal_year, doc_date_utc, doc_date_local)
        VALUES ('X4', 'F1', 1, 1, 'U1', 'U1', NULL, 'D1', 'h', 1,
          'sale_invoice', 'INV-2627-0003', 'INV', 3, 2627, 1, '2026-08-23')
      '''),
        _throwsSqlite('UNIQUE constraint failed'),
      );
    },
  );

  test('the database itself refuses an unbalanced journal entry', () {
    // Belt and braces with assertBooksBalance(). The application check catches
    // it with a useful message; this catches it if anyone ever writes to the
    // table by another route.
    expect(
      db.customStatement('''
        INSERT INTO journal_entries ($_env, entry_no, entry_date_utc,
          entry_date_local, fiscal_year, source_type, total_debit_paisa,
          total_credit_paisa)
        VALUES ('J1', 'F1', 1, 1, 'U1', 'U1', NULL, 'D1', 'h', 1,
          'JV-1', 1, '2026-08-23', 2627, 'sale', 552500, 552400)
      '''),
      _throwsSqlite('CHECK constraint failed'),
    );
  });

  test('a journal line must carry exactly one side', () async {
    await db.customStatement('''
      INSERT INTO journal_entries ($_env, entry_no, entry_date_utc,
        entry_date_local, fiscal_year, source_type, total_debit_paisa,
        total_credit_paisa)
      VALUES ('J2', 'F1', 1, 1, 'U1', 'U1', NULL, 'D1', 'h', 1,
        'JV-2', 1, '2026-08-23', 2627, 'sale', 0, 0)
    ''');

    Future<void> insertLine(int debit, int credit, String id) =>
        db.customStatement('''
          INSERT INTO journal_lines ($_env, journal_entry_id, line_no,
            account_id, debit_paisa, credit_paisa)
          VALUES ('$id', 'F1', 1, 1, 'U1', 'U1', NULL, 'D1', 'h', 1,
            'J2', 1, 'A-CASH', $debit, $credit)
        ''');

    // Both sides filled: a bug someone would spend a week finding six months
    // from now.
    expect(
      insertLine(100, 100, 'L1'),
      _throwsSqlite('CHECK constraint failed'),
    );
    // Both sides zero: noise in the ledger.
    expect(insertLine(0, 0, 'L2'), _throwsSqlite('CHECK constraint failed'));
  });

  test('the stock ledger refuses a movement of zero', () {
    // An append-only ledger row that moves nothing is not a record of
    // anything. It is a row someone forgot to fill in.
    expect(
      db.customStatement('''
        INSERT INTO stock_ledger ($_env, item_id, txn_type,
          qty_delta_thousandths, occurred_at_utc, occurred_on_local)
        VALUES ('S1', 'F1', 1, 1, 'U1', 'U1', NULL, 'D1', 'h', 1,
          'I-ATTA', 'sale', 0, 1, '2026-08-23')
      '''),
      _throwsSqlite('CHECK constraint failed'),
    );
  });

  test('a cheque payment without a cheque number is rejected', () {
    expect(
      db.customStatement('''
        INSERT INTO payments ($_env, payment_no, direction,
          payment_account_id, mode, amount_paisa, payment_date_utc,
          payment_date_local)
        VALUES ('P1', 'F1', 1, 1, 'U1', 'U1', NULL, 'D1', 'h', 1,
          'RCV-1', 'in', 'PA-CASH', 'cheque', 100000, 1, '2026-08-23')
      '''),
      _throwsSqlite('CHECK constraint failed'),
    );
  });

  test('an unknown payment mode is rejected', () {
    // The mode is a label, but it is a label from a closed set. A typo must
    // not create a payment method that no report knows about.
    expect(
      db.customStatement('''
        INSERT INTO payments ($_env, payment_no, direction,
          payment_account_id, mode, amount_paisa, payment_date_utc,
          payment_date_local)
        VALUES ('P2', 'F1', 1, 1, 'U1', 'U1', NULL, 'D1', 'h', 1,
          'RCV-2', 'in', 'PA-CASH', 'sadapay', 100000, 1, '2026-08-23')
      '''),
      _throwsSqlite('CHECK constraint failed'),
    );
  });

  test('a nonsense cash tender is rejected', () {
    // Tendered less than the amount due means the cashier mistyped, and the
    // change this would compute is negative.
    expect(
      db.customStatement('''
        INSERT INTO payments ($_env, payment_no, direction,
          payment_account_id, mode, amount_paisa, tendered_paisa,
          payment_date_utc, payment_date_local)
        VALUES ('P3', 'F1', 1, 1, 'U1', 'U1', NULL, 'D1', 'h', 1,
          'RCV-3', 'in', 'PA-CASH', 'cash', 552500, 500000, 1, '2026-08-23')
      '''),
      _throwsSqlite('CHECK constraint failed'),
    );
  });

  test(
    'a deferred foreign key lets a transaction insert in any order',
    () async {
      // Lines before their document. This is why the envelope keys are
      // DEFERRABLE INITIALLY DEFERRED: a batched write should not have to be
      // topologically sorted to succeed.
      await db.transaction(() async {
        await db.customStatement('''
        INSERT INTO document_lines ($_env, document_id, line_no,
          item_name_snapshot, qty_thousandths, unit_code_snapshot,
          base_qty_thousandths, rate_milli_paisa)
        VALUES ('DL1', 'F1', 1, 1, 'U1', 'U1', NULL, 'D1', 'h', 1,
          'X9', 1, 'Atta 10kg', 1000, 'bag', 1000, 132000000)
      ''');
        await db.customStatement('''
        INSERT INTO documents ($_env, doc_type, doc_no, doc_series, doc_seq,
          fiscal_year, doc_date_utc, doc_date_local)
        VALUES ('X9', 'F1', 1, 1, 'U1', 'U1', NULL, 'D1', 'h', 1,
          'sale_invoice', 'INV-2627-0009', 'INV', 9, 2627, 1, '2026-08-23')
      ''');
      });

      final lines = await db
          .customSelect("SELECT * FROM document_lines WHERE document_id = 'X9'")
          .get();
      expect(lines, hasLength(1));
    },
  );

  test(
    'a deferred foreign key still fails the whole transaction at commit',
    () async {
      // Deferred is not lenient. It is later.
      await expectLater(
        db.transaction(() async {
          await db.customStatement('''
          INSERT INTO document_lines ($_env, document_id, line_no,
            item_name_snapshot, qty_thousandths, unit_code_snapshot,
            base_qty_thousandths, rate_milli_paisa)
          VALUES ('DL2', 'F1', 1, 1, 'U1', 'U1', NULL, 'D1', 'h', 1,
            'never-inserted', 1, 'Atta 10kg', 1000, 'bag', 1000, 132000000)
        ''');
        }),
        _throwsSqlite('FOREIGN KEY constraint failed'),
      );

      final leftovers = await db
          .customSelect('SELECT * FROM document_lines')
          .get();
      expect(
        leftovers,
        isEmpty,
        reason: 'a failed commit must leave nothing behind',
      );
    },
  );
}

/// The universal row envelope, as a column list for raw INSERTs.
const _env =
    'id, firm_id, created_at_utc, updated_at_utc, created_by, '
    'updated_by, deleted_at_utc, origin_device_id, hlc, rev';

/// The minimum rows first run must write before anything else can exist.
Future<void> _seedFirstRun(AppDatabase db) async {
  await db.customStatement('''
    INSERT INTO firms ($_env, name, city)
    VALUES ('F1', 'F1', 1, 1, 'U1', 'U1', NULL, 'D1', 'h', 1,
      'Chishti Kiryana Store', 'Lahore')
  ''');
  await db.customStatement('''
    INSERT INTO devices ($_env, label, platform)
    VALUES ('D1', 'F1', 1, 1, 'U1', 'U1', NULL, 'D1', 'h', 1,
      'Counter 1', 'test')
  ''');
  await db.customStatement('''
    INSERT INTO users ($_env, name, role)
    VALUES ('U1', 'F1', 1, 1, 'U1', 'U1', NULL, 'D1', 'h', 1,
      'Malik Sahib', 'owner')
  ''');
  await db.customStatement('''
    INSERT INTO accounts ($_env, code, name, account_type, normal_side,
      system_key)
    VALUES ('A-CASH', 'F1', 1, 1, 'U1', 'U1', NULL, 'D1', 'h', 1,
      '1010', 'Cash in Hand', 'asset', 'debit', 'cash_in_hand')
  ''');
  await db.customStatement('''
    INSERT INTO payment_accounts ($_env, name, account_kind, mode_label,
      ledger_account_id, is_default)
    VALUES ('PA-CASH', 'F1', 1, 1, 'U1', 'U1', NULL, 'D1', 'h', 1,
      'Golak', 'cash', 'cash', 'A-CASH', 1)
  ''');
  await db.customStatement('''
    INSERT INTO units ($_env, code, name_en, name_ur, kind, is_base, decimals)
    VALUES ('U-G', 'F1', 1, 1, 'U1', 'U1', NULL, 'D1', 'h', 1,
      'g', 'Gram', 'Gram', 'weight', 1, 3)
  ''');
  await db.customStatement('''
    INSERT INTO items ($_env, name, name_search, base_unit_id,
      sale_rate_milli_paisa)
    VALUES ('I-ATTA', 'F1', 1, 1, 'U1', 'U1', NULL, 'D1', 'h', 1,
      'Atta', 'atta', 'U-G', 1320)
  ''');
}

Matcher _throwsSqlite(String fragment) => throwsA(
  predicate<Object>(
    (e) => e.toString().contains(fragment),
    'a SQLite error mentioning "$fragment"',
  ),
);
