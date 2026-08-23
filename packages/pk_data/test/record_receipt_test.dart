import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// A customer paying off their khata, against a real database.
///
/// The builder tests prove the arithmetic. These prove the rows land: that
/// the bills actually come down, that the books still balance afterwards,
/// that a customer paying too much leaves a liability rather than a negative
/// asset, and that a failure part-way through leaves nothing behind.
void main() {
  late AppDatabase db;
  late FixedClock clock;
  late UlidGenerator ids;
  late FirstRunResult firm;
  late TxRunner runner;
  late PostSaleUseCase postSale;
  late RecordReceiptUseCase recordReceipt;
  late ActorContext actor;
  late String partyId;
  late String oilId;
  late String cashAccountId;
  late String pcsUnitId;

  setUp(() async {
    db = await openTestDatabase();
    clock = FixedClock(DateTime.utc(2026, 8, 23, 9, 15));
    ids = UlidGenerator(now: clock.nowUtc);

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
    postSale = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));
    recordReceipt = RecordReceiptUseCase(
      writer: DriftPaymentWriter(runner: runner),
    );

    pcsUnitId =
        (await db.customSelect("SELECT id FROM units WHERE code = 'pcs'").get())
            .first
            .read<String>('id');

    cashAccountId =
        (await db
                .customSelect(
                  'SELECT id FROM payment_accounts WHERE is_default = 1',
                )
                .get())
            .first
            .read<String>('id');

    await runner.run(actor, (tx) async {
      partyId = await tx.insert('parties', {
        'name': 'Rashid Traders',
        'name_search': 'rashid traders',
        'party_type': 'customer',
      });
      oilId = await tx.insert('items', {
        'name': 'Cooking Oil 5L',
        'name_search': 'cooking oil 5l',
        'base_unit_id': pcsUnitId,
        'sale_rate_milli_paisa': Rate.rupees(1000).inMilliPaisa,
      });
    });
  });

  tearDown(() async => db.close());

  /// A credit sale of [rupees] to the party, leaving the whole thing unpaid.
  Future<String> udhaarSale(int rupees, {String? onDate}) async {
    final at = onDate == null
        ? actor
        : ActorContext(
            firmId: firm.firmId,
            userId: firm.ownerUserId,
            deviceId: firm.deviceId,
            startedAtUtc: DateTime.parse('${onDate}T09:00:00Z'),
          );
    final posted = await postSale(
      at,
      SaleDraft(
        partyId: partyId,
        lines: [
          SaleLineDraft(
            itemId: oilId,
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

  Future<RecordedReceipt> receive(
    int rupees, {
    String mode = 'cash',
    String? chequeNo,
  }) => recordReceipt(
    actor,
    ReceiptDraft(
      partyId: partyId,
      amount: Money.rupees(rupees),
      mode: mode,
      chequeNo: chequeNo,
      paymentAccountId: cashAccountId,
    ),
  );

  Future<int> balanceOf(String documentId) async =>
      (await db
              .customSelect(
                'SELECT balance_paisa FROM documents WHERE id = ?',
                variables: [Variable<String>(documentId)],
              )
              .getSingle())
          .read<int>('balance_paisa');

  test(
    'a payment clears the oldest bills and the balances come down',
    () async {
      final first = await udhaarSale(3000, onDate: '2026-06-01');
      final second = await udhaarSale(1500, onDate: '2026-07-15');

      final receipt = await receive(4000);

      expect(receipt.applied, const Money.rupees(4000));
      expect(receipt.unapplied, Money.zero);
      expect(receipt.settledDocumentIds, [first, second]);
      expect(await balanceOf(first), 0);
      expect(await balanceOf(second), const Money.rupees(500).inPaisa);
    },
  );

  test('the books still balance afterwards', () async {
    // The guarantee the whole write path exists for. TxRunner asserts it at
    // exact integer equality before commit, so this passing means the
    // assertion ran and agreed rather than that nobody looked.
    await udhaarSale(3000);
    await receive(1200);

    final totals = await db
        .customSelect(
          'SELECT SUM(debit_paisa) AS d, SUM(credit_paisa) AS c '
          'FROM journal_lines',
        )
        .getSingle();

    expect(totals.read<int>('d'), totals.read<int>('c'));
  });

  test(
    'paying more than is owed leaves a liability, not a negative bill',
    () async {
      // A customer settling up and rounding to the next thousand, which is
      // ordinary. The overshoot must not push a bill below zero, and must not
      // sit in Receivables as a negative asset where no report can find it.
      final bill = await udhaarSale(3000);

      final receipt = await receive(5000);

      expect(receipt.applied, const Money.rupees(3000));
      expect(receipt.unapplied, const Money.rupees(2000));
      expect(await balanceOf(bill), 0);

      final advances = await db.customSelect('''
          SELECT COALESCE(SUM(jl.credit_paisa - jl.debit_paisa), 0) AS net
          FROM journal_lines jl
          JOIN accounts a ON a.id = jl.account_id
          WHERE a.system_key = 'customer_advances'
          ''').getSingle();

      expect(advances.read<int>('net'), const Money.rupees(2000).inPaisa);
    },
  );

  test('a customer with no open bills pays entirely on account', () async {
    final receipt = await receive(2500);

    expect(receipt.applied, Money.zero);
    expect(receipt.unapplied, const Money.rupees(2500));
    expect(receipt.settledDocumentIds, isEmpty);
  });

  test('the allocations record which bills, and for how much', () async {
    // The question every shopkeeper is asked and could not previously answer.
    final first = await udhaarSale(3000, onDate: '2026-06-01');
    await udhaarSale(1500, onDate: '2026-07-15');

    await receive(3200);

    final rows = await db
        .customSelect(
          'SELECT document_id, amount_paisa, allocation_mode '
          'FROM payment_allocations ORDER BY amount_paisa DESC',
        )
        .get();

    expect(rows, hasLength(2));
    expect(rows.first.read<String>('document_id'), first);
    expect(
      rows.first.read<int>('amount_paisa'),
      const Money.rupees(3000).inPaisa,
    );
    expect(rows.first.read<String>('allocation_mode'), 'fifo');
  });

  test('a cheque is pending and sits in Cheques in Hand', () async {
    await udhaarSale(3000);

    await receive(3000, mode: 'cheque', chequeNo: '000123');

    final payment = await db
        .customSelect('SELECT status, cheque_status FROM payments')
        .getSingle();
    expect(payment.read<String>('status'), 'pending');
    expect(payment.read<String>('cheque_status'), 'issued');

    final cheques = await db.customSelect('''
          SELECT COALESCE(SUM(jl.debit_paisa), 0) AS held
          FROM journal_lines jl
          JOIN accounts a ON a.id = jl.account_id
          WHERE a.system_key = 'cheques_in_hand'
          ''').getSingle();
    expect(cheques.read<int>('held'), const Money.rupees(3000).inPaisa);
  });

  test('a void bill is never paid against', () async {
    // Allocating onto a void document is money the customer's khata gains
    // that nobody returned, and findOverAllocatedPayments() cannot catch it
    // because the sum still fits.
    final voided = await udhaarSale(3000, onDate: '2026-06-01');
    final live = await udhaarSale(1000, onDate: '2026-07-01');
    await runner.run(actor, (tx) async {
      await tx.update('documents', voided, {'status': 'void'});
    });

    final receipt = await receive(1000);

    expect(receipt.settledDocumentIds, [live]);
    expect(await balanceOf(voided), const Money.rupees(3000).inPaisa);
  });

  test('a receipt is recorded in the audit trail with its own words', () async {
    await udhaarSale(3000);
    final receipt = await receive(1000);

    final audit = await db
        .customSelect(
          'SELECT action_code, entity_id, summary, amount_paisa FROM audit_log '
          "WHERE action_code = 'PAYMENT_RECEIVED'",
        )
        .getSingle();

    expect(audit.read<String>('entity_id'), receipt.paymentId);
    expect(audit.read<int>('amount_paisa'), const Money.rupees(1000).inPaisa);
    expect(audit.read<String>('summary'), contains('1,000.00'));
  });

  test(
    'a receipt reaches the outbox so a second till can learn of it',
    () async {
      await udhaarSale(3000);
      await receive(1000);

      final changed = await db
          .customSelect(
            'SELECT DISTINCT entity_table FROM change_log ORDER BY entity_table',
          )
          .get();
      final tables = changed.map((r) => r.read<String>('entity_table')).toSet();

      expect(tables, containsAll(['payments', 'payment_allocations']));
    },
  );

  test('a failure part-way through leaves nothing behind', () async {
    // The whole point of one transaction, and it has to fail LATE to prove
    // anything. The first version of this used a payment account that did not
    // exist, which fails before a single row is written — a rollback test
    // that never reaches the thing it claims to test.
    //
    // So instead the Customer Advances account is removed behind the writer's
    // back, and the customer overpays. The payment row and its allocations
    // are already inserted by the time the journal cannot find the account.
    await udhaarSale(3000);
    await db.customStatement(
      'UPDATE accounts SET deleted_at_utc = 1 '
      "WHERE system_key = 'customer_advances'",
    );

    // Counted before and after, not asserted at zero: the sale that created
    // the udhaar legitimately wrote journal lines of its own, and a test that
    // demanded an empty table would have been asserting the sale away.
    Future<Map<String, int>> counts() async {
      final result = <String, int>{};
      for (final table in const [
        'payments',
        'payment_allocations',
        'journal_entries',
        'journal_lines',
        'audit_log',
        'change_log',
      ]) {
        result[table] =
            (await db
                    .customSelect('SELECT COUNT(*) AS n FROM $table')
                    .getSingle())
                .read<int>('n');
      }
      return result;
    }

    final before = await counts();
    await expectLater(receive(5000), throwsA(isA<StateError>()));

    expect(
      await counts(),
      before,
      reason: 'a receipt that failed left rows behind',
    );

    // And the bill it had started settling is untouched.
    final bill = await db
        .customSelect('SELECT balance_paisa FROM documents')
        .getSingle();
    expect(bill.read<int>('balance_paisa'), const Money.rupees(3000).inPaisa);
  });

  test('a receipt number is never burned by a failure', () async {
    // A gap in a receipt series is the first thing an auditor asks about.
    await udhaarSale(3000);
    await expectLater(
      recordReceipt(
        actor,
        ReceiptDraft(
          partyId: partyId,
          amount: const Money.rupees(1000),
          mode: 'cheque',
          paymentAccountId: cashAccountId,
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );

    final receipt = await receive(1000);
    expect(receipt.paymentNo, endsWith('0001'));
  });
}
