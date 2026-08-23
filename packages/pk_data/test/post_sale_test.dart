import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// The M0 acceptance script, run against a real database file.
///
/// This is the test the previous build could not have written. Its checkout
/// showed a SnackBar saying "Sale processed via Cash! Thermal receipt printed."
/// and then cleared the cart; `grep InvoicesCompanion.insert lib/` returned
/// nothing anywhere in the repository, and twenty-five tests passed anyway
/// because two of the test files imported no project code at all.
///
/// Every assertion below reads what is actually in the database.
void main() {
  late AppDatabase db;
  late FixedClock clock;
  late UlidGenerator ids;
  late FirstRunResult firm;
  late PostSaleUseCase postSale;
  late ActorContext actor;
  late String oilId;
  late String muttonId;
  late String pcsUnitId;
  late String kgUnitId;

  setUp(() async {
    db = await openTestDatabase();
    // 2:15pm in Lahore on 23 August 2026 — a Sunday afternoon, mid FY 2026-27.
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
    final runner = TxRunner(database: db, ids: ids, hlc: hlc);
    postSale = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));

    pcsUnitId = await _unitId(db, 'pcs');
    kgUnitId = await _unitId(db, 'kg');

    // Two items, added the way the quick-add screen will add them.
    await runner.run(actor, (tx) async {
      oilId = await tx.insert('items', {
        'name': 'Cooking Oil 5L',
        'name_search': 'cooking oil 5l',
        'base_unit_id': pcsUnitId,
        'sale_rate_milli_paisa': Rate.rupees(2500).inMilliPaisa,
      });
      muttonId = await tx.insert('items', {
        'name': 'Mutton',
        'name_search': 'mutton',
        'base_unit_id': kgUnitId,
        'sale_rate_milli_paisa': Rate.rupees(150).inMilliPaisa,
      });
    });
  });

  tearDown(() async => db.close());

  SaleDraft referenceSale({List<TenderDraft>? tenders, String? partyId}) =>
      SaleDraft(
        partyId: partyId,
        lines: [
          SaleLineDraft(
            itemId: oilId,
            itemName: 'Cooking Oil 5L',
            qty: Qty.units(2),
            baseQty: Qty.units(2),
            unitId: pcsUnitId,
            unitCode: 'pcs',
            rate: Rate.rupees(2500),
          ),
          SaleLineDraft(
            itemId: muttonId,
            itemName: 'Mutton',
            qty: Qty.parse('3.5'),
            baseQty: Qty.parse('3.5'),
            unitId: kgUnitId,
            unitCode: 'kg',
            rate: Rate.rupees(150),
          ),
        ],
        tenders:
            tenders ??
            const [
              TenderDraft(
                paymentAccountId: '',
                mode: 'cash',
                amount: Money.rupees(6000),
                tendered: Money.rupees(6000),
              ),
            ],
      );

  group('step 7 — the sale is really in the database', () {
    late PostedSale result;

    setUp(() async {
      result = await postSale(
        actor,
        referenceSale(
          tenders: [
            TenderDraft(
              paymentAccountId: firm.cashPaymentAccountId,
              mode: 'cash',
              amount: Money.rupees(6000),
              tendered: Money.rupees(6000),
            ),
          ],
        ),
      );
    });

    test(
      'one document, numbered INV-2627-0001, totalling 552500 paisa',
      () async {
        final rows = await db.customSelect('SELECT * FROM documents').get();
        expect(rows, hasLength(1));

        final doc = rows.single;
        expect(doc.read<String>('doc_no'), 'INV-2627-0001');
        expect(doc.read<int>('total_paisa'), 552500);
        expect(doc.read<String>('doc_type'), 'sale_invoice');
        expect(doc.read<String>('status'), 'posted');
        expect(doc.read<int>('fiscal_year'), 2627);
        expect(doc.read<String>('doc_date_local'), '2026-08-23');
        expect(doc.read<int>('paid_paisa'), 552500);
        expect(doc.read<int>('balance_paisa'), 0);
        expect(doc.read<String>('tax_rule_version'), 'untaxed-v1');
        expect(doc.read<String>('rounding_mode'), 'half_up');
        expect(doc.read<int>('cash_threshold_breached'), 0);
        expect(doc.readNullable<int>('posted_at_utc'), isNotNull);

        expect(result.docNo, 'INV-2627-0001');
        expect(result.total, Money.rupees(5525));
        expect(result.change, Money.rupees(475));
        expect(result.documentId, doc.read<String>('id'));
      },
    );

    test('two lines, with the fractional weight intact', () async {
      final lines = await db
          .customSelect('SELECT * FROM document_lines ORDER BY line_no')
          .get();
      expect(lines, hasLength(2));

      expect(lines[0].read<int>('qty_thousandths'), 2000);
      expect(lines[0].read<int>('rate_milli_paisa'), 250000000);
      expect(lines[0].read<int>('line_total_paisa'), 500000);
      expect(lines[0].read<String>('unit_code_snapshot'), 'pcs');

      // 3.5 kg, stored as 3500 thousandths of a kilo. The previous build
      // rendered `quantity.toInt()` here and showed the cashier a zero.
      expect(lines[1].read<int>('qty_thousandths'), 3500);
      expect(lines[1].read<int>('line_total_paisa'), 52500);
      expect(lines[1].read<String>('unit_code_snapshot'), 'kg');
      expect(Qty.raw(lines[1].read<int>('qty_thousandths')).display, '3.5');

      // The snapshot, not a join. An item renamed next month must not rewrite
      // what this invoice says.
      expect(lines[1].read<String>('item_name_snapshot'), 'Mutton');
    });

    test('one payment and one allocation, with the change recorded', () async {
      final payments = await db.customSelect('SELECT * FROM payments').get();
      expect(payments, hasLength(1));
      expect(payments.single.read<int>('amount_paisa'), 552500);
      expect(payments.single.read<int>('tendered_paisa'), 600000);
      expect(payments.single.read<int>('change_paisa'), 47500);
      expect(payments.single.read<String>('mode'), 'cash');
      expect(payments.single.read<String>('status'), 'cleared');

      final allocations = await db
          .customSelect('SELECT * FROM payment_allocations')
          .get();
      expect(allocations, hasLength(1));
      expect(allocations.single.read<int>('amount_paisa'), 552500);
      expect(allocations.single.read<String>('document_id'), result.documentId);
    });

    test('two stock movements, out of the shop', () async {
      final stock = await db
          .customSelect('SELECT * FROM stock_ledger ORDER BY id')
          .get();
      expect(stock, hasLength(2));

      final deltas = [
        for (final s in stock) s.read<int>('qty_delta_thousandths'),
      ];
      expect(deltas, containsAll([-2000, -3500]));
      for (final s in stock) {
        expect(s.read<String>('txn_type'), 'sale');
        expect(s.read<String>('location_code'), 'MAIN');
        expect(s.read<String>('document_id'), result.documentId);
        expect(s.readNullable<String>('document_line_id'), isNotNull);
        expect(s.read<String>('occurred_on_local'), '2026-08-23');
      }
    });

    test('the journal balances at 552500 on both sides', () async {
      final entries = await db
          .customSelect('SELECT * FROM journal_entries')
          .get();
      expect(entries, hasLength(1));
      expect(entries.single.read<String>('entry_no'), 'JV-2627-00001');
      expect(entries.single.read<String>('source_type'), 'sale');
      expect(entries.single.read<String>('document_id'), result.documentId);

      final totals = await db
          .customSelect(
            'SELECT SUM(debit_paisa) AS d, SUM(credit_paisa) AS c '
            'FROM journal_lines',
          )
          .getSingle();
      expect(totals.read<int>('d'), 552500);
      expect(totals.read<int>('c'), 552500);

      // Cash in, sales out. Nothing else, because nothing was bought yet so
      // there is no cost to post.
      final lines = await db.customSelect('''
            SELECT a.system_key AS k, jl.debit_paisa AS d, jl.credit_paisa AS c
            FROM journal_lines jl
            JOIN accounts a ON a.id = jl.account_id
            ORDER BY jl.line_no
          ''').get();
      expect(lines, hasLength(2));
      expect(lines[0].read<String>('k'), 'cash_in_hand');
      expect(lines[0].read<int>('d'), 552500);
      expect(lines[1].read<String>('k'), 'sales');
      expect(lines[1].read<int>('c'), 552500);

      expect(await db.findLedgerImbalances(), isEmpty);
    });

    test(
      'the audit trail names the action, the actor and the amount',
      () async {
        final rows = await db
            .customSelect(
              "SELECT * FROM audit_log WHERE action_code = 'SALE_POSTED'",
            )
            .get();
        expect(rows, hasLength(1));
        expect(rows.single.read<String>('created_by'), firm.ownerUserId);
        expect(rows.single.read<String>('origin_device_id'), firm.deviceId);
        expect(rows.single.read<String>('entity_id'), result.documentId);
        expect(rows.single.read<int>('amount_paisa'), 552500);
        expect(
          rows.single.read<String>('summary'),
          allOf(contains('INV-2627-0001'), contains('5,525.00')),
        );
      },
    );

    test('the outbox knows about every row the sale wrote', () async {
      final rows = await db
          .customSelect(
            'SELECT entity_table, COUNT(*) AS n FROM change_log '
            'GROUP BY entity_table',
          )
          .get();
      final byTable = {
        for (final r in rows) r.read<String>('entity_table'): r.read<int>('n'),
      };
      expect(byTable['documents'], 1);
      expect(byTable['document_lines'], 2);
      expect(byTable['payments'], 1);
      expect(byTable['payment_allocations'], 1);
      expect(byTable['stock_ledger'], 2);
      expect(byTable['journal_entries'], 1);
      expect(byTable['journal_lines'], 2);
    });

    test('the database is healthy afterwards', () async {
      final health = await db.checkHealth();
      expect(health.isHealthy, isTrue, reason: health.toString());
    });
  });

  group('step 11 — fault injection', () {
    test('a failure part-way through leaves all nine tables empty', () async {
      // The plan's hard acceptance gate. If the write path can ever leave a
      // half-written sale behind, every report built on top of it is wrong and
      // the shopkeeper has no way to find out.
      final failing = PostSaleUseCase(
        writer: _FailAfterDocument(
          DriftSaleWriter(
            runner: TxRunner(
              database: db,
              ids: ids,
              hlc: await resumeHlcClock(
                db,
                deviceId: firm.deviceId,
                clock: clock,
              ),
            ),
          ),
        ),
      );

      await expectLater(
        failing(
          actor,
          referenceSale(
            tenders: [
              TenderDraft(
                paymentAccountId: firm.cashPaymentAccountId,
                mode: 'cash',
                amount: Money.rupees(6000),
              ),
            ],
          ),
        ),
        throwsA(isA<StateError>()),
      );

      for (final table in const [
        'documents',
        'document_lines',
        'document_line_taxes',
        'doc_links',
        'payments',
        'payment_allocations',
        'stock_ledger',
        'journal_entries',
        'journal_lines',
      ]) {
        final row = await db
            .customSelect('SELECT COUNT(*) AS n FROM $table')
            .getSingle();
        expect(row.read<int>('n'), 0, reason: '$table must be empty');
      }
    });

    test('a burnt invoice number is given back', () async {
      // A gap in an invoice series is the first thing an auditor asks about,
      // and the shopkeeper has to be able to answer.
      final before = await _nextInvoiceValue(db);

      final failing = PostSaleUseCase(
        writer: _FailAfterDocument(
          DriftSaleWriter(
            runner: TxRunner(
              database: db,
              ids: ids,
              hlc: await resumeHlcClock(
                db,
                deviceId: firm.deviceId,
                clock: clock,
              ),
            ),
          ),
        ),
      );
      await expectLater(
        failing(
          actor,
          referenceSale(
            tenders: [
              TenderDraft(
                paymentAccountId: firm.cashPaymentAccountId,
                mode: 'cash',
                amount: Money.rupees(6000),
              ),
            ],
          ),
        ),
        throwsA(isA<StateError>()),
      );

      expect(await _nextInvoiceValue(db), before);

      // And the next real sale still gets 0001.
      final ok = await postSale(
        actor,
        referenceSale(
          tenders: [
            TenderDraft(
              paymentAccountId: firm.cashPaymentAccountId,
              mode: 'cash',
              amount: Money.rupees(6000),
            ),
          ],
        ),
      );
      expect(ok.docNo, 'INV-2627-0001');
    });
  });

  group('selling on udhaar', () {
    test('an unpaid sale becomes a receivable against the party', () async {
      final partyId =
          await TxRunner(
            database: db,
            ids: ids,
            hlc: await resumeHlcClock(
              db,
              deviceId: firm.deviceId,
              clock: clock,
            ),
          ).run(
            actor,
            (tx) => tx.insert('parties', {
              'name': 'Bilal General Store',
              'name_search': 'bilal general store',
              'party_type': 'customer',
            }),
          );

      final result = await postSale(
        actor,
        SaleDraft(
          partyId: partyId,
          partyName: 'Bilal General Store',
          lines: referenceSale().lines,
          tenders: [
            TenderDraft(
              paymentAccountId: firm.cashPaymentAccountId,
              mode: 'cash',
              amount: Money.rupees(2000),
            ),
          ],
        ),
      );

      expect(result.paid, Money.rupees(2000));
      expect(result.balance, Money.rupees(3525));

      final line = await db.customSelect('''
            SELECT jl.debit_paisa AS d, jl.party_id AS p
            FROM journal_lines jl
            JOIN accounts a ON a.id = jl.account_id
            WHERE a.system_key = 'accounts_receivable'
          ''').getSingle();
      expect(line.read<int>('d'), 352500);
      expect(line.read<String>('p'), partyId);
      expect(await db.findLedgerImbalances(), isEmpty);
    });
  });

  group('two sales in a row', () {
    test('number consecutively and never collide', () async {
      final first = await postSale(
        actor,
        referenceSale(
          tenders: [
            TenderDraft(
              paymentAccountId: firm.cashPaymentAccountId,
              mode: 'cash',
              amount: Money.rupees(6000),
            ),
          ],
        ),
      );
      clock.advance(const Duration(minutes: 3));
      final second = await postSale(
        firm.actorAt(clock.nowUtc()),
        referenceSale(
          tenders: [
            TenderDraft(
              paymentAccountId: firm.cashPaymentAccountId,
              mode: 'cash',
              amount: Money.rupees(6000),
            ),
          ],
        ),
      );

      expect(first.docNo, 'INV-2627-0001');
      expect(second.docNo, 'INV-2627-0002');

      final stock = await db
          .customSelect(
            '''
            SELECT balance_after_thousandths AS b
            FROM stock_ledger
            WHERE item_id = ?
            ORDER BY occurred_at_utc, id
          ''',
            variables: [Variable<String>(muttonId)],
          )
          .get();
      expect([for (final s in stock) s.read<int>('b')], [-3500, -7000]);
      expect(await db.findLedgerImbalances(), isEmpty);
    });
  });
}

Future<String> _unitId(AppDatabase db, String code) async {
  final row = await db
      .customSelect(
        'SELECT id FROM units WHERE code = ?',
        variables: [Variable<String>(code)],
      )
      .getSingle();
  return row.read<String>('id');
}

Future<int> _nextInvoiceValue(AppDatabase db) async {
  final row = await db
      .customSelect(
        'SELECT next_value FROM numbering_sequences '
        "WHERE doc_type = 'sale_invoice'",
      )
      .getSingle();
  return row.read<int>('next_value');
}

/// Injects a fault after the document row is written, and nowhere else.
class _FailAfterDocument implements SaleWriter {
  const _FailAfterDocument(this._inner);

  final SaleWriter _inner;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(SaleWriteContext write) body,
  ) => _inner.inTransaction(actor, (write) => body(_FaultyContext(write)));
}

class _FaultyContext implements SaleWriteContext {
  const _FaultyContext(this._inner);

  final SaleWriteContext _inner;

  @override
  ActorContext get actor => _inner.actor;

  @override
  Future<TaxContext> taxContextFor(String? partyId) =>
      _inner.taxContextFor(partyId);

  @override
  Future<AllocatedNumber> nextNumber(String docType) =>
      _inner.nextNumber(docType);

  @override
  Future<Map<String, Rate>> averageCostFor(Iterable<String> itemIds) =>
      _inner.averageCostFor(itemIds);

  @override
  Future<Map<String, String>> ledgerAccountsFor(Iterable<String> ids) =>
      _inner.ledgerAccountsFor(ids);

  @override
  Future<PostedSale> apply(SalePosting posting) async {
    // Write only the document, then fall over — the exact shape of a crash
    // between two inserts.
    await _inner.apply(
      SalePosting(
        document: posting.document,
        lines: const [],
        payments: const [],
        stockMovements: const [],
        journal: JournalEntryPosting(
          entryNo: posting.journal.entryNo,
          entryDateUtcMillis: posting.journal.entryDateUtcMillis,
          entryDateLocal: posting.journal.entryDateLocal,
          fiscalYear: posting.journal.fiscalYear,
          sourceType: posting.journal.sourceType,
          totalDebit: Money.zero,
          totalCredit: Money.zero,
          lines: const [],
        ),
        auditSummary: posting.auditSummary,
      ),
    );
    throw StateError('injected fault after the document insert');
  }
}
