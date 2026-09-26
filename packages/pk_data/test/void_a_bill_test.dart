import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// Undoing a bill, against a real database.
///
/// The builder tests prove the mirror. These prove the ledger stays
/// append-only, the stock comes back at the cost it left at, and the one
/// refusal that matters actually fires — a bill with a payment against it
/// cannot be voided, because `findOverAllocatedPayments()` would never notice
/// the allocation left pointing at nothing.
void main() {
  late AppDatabase db;
  late UlidGenerator ids;
  late FirstRunResult firm;
  late TxRunner runner;
  late DriftAppQueries queries;
  late PostSaleUseCase postSale;
  late RecordReceiptUseCase receive;
  late VoidDocumentUseCase voidDocument;
  late ActorContext actor;
  late String pcsUnitId;
  late String riceId;
  late String partyId;
  late String cashAccountId;

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
    actor = firm.actorAt(clock.nowUtc());
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    queries = DriftAppQueries(db);
    postSale = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));
    receive = RecordReceiptUseCase(writer: DriftPaymentWriter(runner: runner));
    voidDocument = VoidDocumentUseCase(writer: DriftVoidWriter(runner: runner));

    pcsUnitId =
        (await db.customSelect("SELECT id FROM units WHERE code = 'pcs'").get())
            .first
            .read<String>('id');
    cashAccountId = (await queries.paymentAccounts(
      firm.firmId,
    )).firstWhere((a) => a.isDefault).id;

    await runner.run(actor, (tx) async {
      partyId = await tx.insert('parties', {
        'name': 'Rashid Traders',
        'name_search': 'rashid traders',
        'party_type': 'customer',
      });
      riceId = await tx.insert('items', {
        'name': 'Chawal Basmati',
        'name_search': 'chawal basmati',
        'base_unit_id': pcsUnitId,
        'sale_rate_milli_paisa': Rate.rupees(150).inMilliPaisa,
        'avg_cost_milli_paisa': Rate.rupees(90).inMilliPaisa,
      });
    });
  });

  tearDown(() async => db.close());

  Future<PostedSale> sell({bool onUdhaar = false, int qty = 2}) => postSale(
    actor,
    SaleDraft(
      partyId: onUdhaar ? partyId : null,
      lines: [
        SaleLineDraft(
          itemId: riceId,
          itemName: 'Chawal Basmati',
          qty: Qty.units(qty),
          baseQty: Qty.units(qty),
          unitId: pcsUnitId,
          unitCode: 'pcs',
          rate: Rate.rupees(150),
        ),
      ],
      tenders: onUdhaar
          ? const []
          : [
              TenderDraft(
                paymentAccountId: cashAccountId,
                mode: 'cash',
                amount: Money.rupees(150 * qty),
              ),
            ],
    ),
  );

  Future<int> countOf(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
          .read<int>('n');

  Future<int> stockBalance() async =>
      (await db
              .customSelect(
                'SELECT COALESCE(SUM(qty_delta_thousandths), 0) AS b '
                'FROM stock_ledger',
              )
              .getSingle())
          .read<int>('b');

  test('the books net to zero after a void', () async {
    final sale = await sell();

    await voidDocument(
      actor,
      documentId: sale.documentId,
      reason: 'Wrong customer',
    );

    // Every account, summed. A reversal that only balances within itself can
    // still leave the shop's position moved; this is the check that it did
    // not.
    final byAccount = await db
        .customSelect(
          'SELECT account_id, SUM(debit_paisa - credit_paisa) AS net '
          'FROM journal_lines GROUP BY account_id',
        )
        .get();

    for (final row in byAccount) {
      expect(
        row.read<int>('net'),
        0,
        reason: 'account ${row.read<String>('account_id')} did not come back',
      );
    }
  });

  test('the stock comes back', () async {
    await sell();
    expect(await stockBalance(), -2000);

    final sale = await db
        .customSelect("SELECT id FROM documents WHERE status = 'posted'")
        .getSingle();
    await voidDocument(
      actor,
      documentId: sale.read<String>('id'),
      reason: 'Never handed over',
    );

    expect(await stockBalance(), 0);
  });

  test('nothing in the ledger is edited, only appended', () async {
    final sale = await sell();
    final entriesBefore = await countOf('journal_entries');
    final linesBefore = await countOf('journal_lines');
    final stockBefore = await countOf('stock_ledger');

    await voidDocument(actor, documentId: sale.documentId, reason: 'Duplicate');

    expect(await countOf('journal_entries'), entriesBefore + 1);
    expect(await countOf('journal_lines'), greaterThan(linesBefore));
    expect(await countOf('stock_ledger'), stockBefore + 1);

    // And the original entry is untouched.
    final original = await db
        .customSelect(
          "SELECT rev FROM journal_entries WHERE source_type = 'sale'",
        )
        .getSingle();
    expect(original.read<int>('rev'), 1);
  });

  test('the reversal points at what it undid', () async {
    final sale = await sell();
    final voided = await voidDocument(
      actor,
      documentId: sale.documentId,
      reason: 'Duplicate',
    );

    final reversal = await db
        .customSelect(
          'SELECT reverses_entry_id, source_type, document_id '
          'FROM journal_entries WHERE id = ?',
          variables: [Variable<String>(voided.reversingEntryId)],
        )
        .getSingle();

    expect(reversal.read<String>('source_type'), 'reversal');
    expect(reversal.read<String>('document_id'), sale.documentId);
    expect(
      reversal.read<String>('reverses_entry_id'),
      sale.journalEntryId,
      reason: 'the pair cannot be found together, so nobody can explain it',
    );
  });

  test('the bill is marked void and keeps its reason', () async {
    final sale = await sell();
    await voidDocument(
      actor,
      documentId: sale.documentId,
      reason: 'Customer changed their mind',
    );

    final doc = await db
        .customSelect(
          'SELECT status, void_reason, doc_no, total_paisa FROM documents '
          'WHERE id = ?',
          variables: [Variable<String>(sale.documentId)],
        )
        .getSingle();

    expect(doc.read<String>('status'), 'void');
    expect(doc.read<String>('void_reason'), 'Customer changed their mind');
    // The bill itself is left exactly as printed, so the paper the customer
    // is holding still matches what the shop has.
    expect(doc.read<String>('doc_no'), sale.docNo);
    expect(doc.read<int>('total_paisa'), sale.total.inPaisa);
  });

  test('a voided udhaar bill leaves the khata clear', () async {
    final sale = await sell(onUdhaar: true);
    expect(
      (await queries.partyById(firm.firmId, partyId))!.balance,
      const Money.rupees(300),
    );

    await voidDocument(
      actor,
      documentId: sale.documentId,
      reason: 'Wrong customer',
    );

    expect(
      (await queries.partyById(firm.firmId, partyId))!.balance,
      Money.zero,
      reason: 'the customer is still being chased for a bill that was undone',
    );
    expect(await queries.openBillsFor(firm.firmId, partyId), isEmpty);
  });

  group('what it refuses', () {
    test('a bill that has been paid against, naming the receipt', () async {
      // The refusal that matters. The naive void leaves an allocation row
      // pointing at a document no report considers real, and
      // findOverAllocatedPayments() cannot catch it because the sum still
      // fits — so the customer's khata quietly gains money nobody returned.
      final sale = await sell(onUdhaar: true);
      final receipt = await receive(
        actor,
        ReceiptDraft(
          partyId: partyId,
          amount: const Money.rupees(100),
          mode: 'cash',
          paymentAccountId: cashAccountId,
        ),
      );

      await expectLater(
        voidDocument(
          actor,
          documentId: sale.documentId,
          reason: 'Wrong customer',
        ),
        throwsA(
          isA<VoidRefused>().having(
            (e) => e.allocations,
            'allocations',
            contains(receipt.paymentNo),
          ),
        ),
      );

      // And nothing was written on the way to refusing.
      final doc = await db
          .customSelect(
            'SELECT status FROM documents WHERE id = ?',
            variables: [Variable<String>(sale.documentId)],
          )
          .getSingle();
      expect(doc.read<String>('status'), 'posted');
      expect(
        await db.findOverAllocatedPayments(),
        isEmpty,
        reason:
            'the health check that cannot see this problem should still be '
            'clean, which is exactly why the refusal has to exist',
      );
    });

    test('a receipt refuses even when it touches this bill alone', () async {
      // The coupling this rests on, asserted rather than trusted.
      //
      // A cash sale writes its own tender and allocates it to itself, so the
      // void path has to tell a counter tender from a receipt taken later.
      // The discriminator is `allocation_mode`: DriftSaleWriter writes
      // `exact`, ReceiptDraft defaults to `fifo`. If a receipt ever started
      // writing `exact`, this bill would silently become voidable and the
      // customer's money would vanish with it.
      final sale = await sell(onUdhaar: true);
      await receive(
        actor,
        ReceiptDraft(
          partyId: partyId,
          amount: const Money.rupees(300),
          mode: 'cash',
          paymentAccountId: cashAccountId,
        ),
      );

      // An udhaar sale writes no tender of its own, so this one allocation
      // is the receipt — and it has to be marked `fifo`, or the void path
      // would read it as a counter tender and let the bill go.
      final allocations = await db
          .customSelect('SELECT allocation_mode FROM payment_allocations')
          .get();
      expect(allocations, hasLength(1));
      expect(
        allocations.single.read<String>('allocation_mode'),
        'fifo',
        reason:
            'a receipt now looks like a sale tender, so the void path cannot '
            'tell them apart and the money would vanish with the bill',
      );

      await expectLater(
        voidDocument(actor, documentId: sale.documentId, reason: 'Wrong'),
        throwsA(isA<VoidRefused>()),
      );
    });

    test('a cash sale can still be voided, tender and all', () async {
      // The other half. The first version of this refusal treated every
      // allocation as an obstacle, which made every cash sale unvoidable.
      final sale = await sell();

      await voidDocument(
        actor,
        documentId: sale.documentId,
        reason: 'Rang up twice',
      );

      final payment = await db
          .customSelect('SELECT status FROM payments')
          .getSingle();
      expect(
        payment.read<String>('status'),
        'void',
        reason:
            'the drawer still claims money came in for a sale that did not '
            'happen',
      );
    });

    test('a bill that is already void', () async {
      final sale = await sell();
      await voidDocument(
        actor,
        documentId: sale.documentId,
        reason: 'Duplicate',
      );

      await expectLater(
        voidDocument(
          actor,
          documentId: sale.documentId,
          reason: 'Duplicate again',
        ),
        throwsA(isA<VoidRefused>()),
      );
    });

    test('a delivery, whose cost cannot be undone by reversing it', () async {
      // A purchase moved the average. Reversing its journal and stock without
      // moving the cost back would leave every margin on a delivery that
      // never happened, so nothing but a sale bill can be voided here.
      final bought =
          await RecordPurchaseUseCase(
            writer: DriftPurchaseWriter(runner: runner),
          )(
            actor,
            PurchaseDraft(
              partyId: partyId,
              lines: [
                PurchaseLineDraft(
                  itemId: riceId,
                  itemName: 'Chawal',
                  qty: Qty.units(10),
                  baseQty: Qty.units(10),
                  unitId: pcsUnitId,
                  unitCode: 'pcs',
                  rate: Rate.rupees(120),
                ),
              ],
            ),
          );
      final entriesBefore = await countOf('journal_entries');

      await expectLater(
        voidDocument(
          actor,
          documentId: bought.documentId,
          reason: 'Wrong quantity',
        ),
        throwsA(isA<VoidRefused>()),
      );
      expect(await countOf('journal_entries'), entriesBefore);
    });

    test('a bill that does not exist', () async {
      await expectLater(
        voidDocument(actor, documentId: 'nothing', reason: 'Typo'),
        throwsA(isA<VoidRefused>()),
      );
    });

    test('a void with no reason, before anything is written', () async {
      final sale = await sell();

      await expectLater(
        voidDocument(actor, documentId: sale.documentId, reason: '  '),
        throwsA(isA<VoidRefused>()),
      );

      expect(await countOf('journal_entries'), 1);
    });
  });

  test('a failed void burns no journal number', () async {
    // A gap in a journal series is the first thing an auditor asks about.
    final sale = await sell(onUdhaar: true);
    await receive(
      actor,
      ReceiptDraft(
        partyId: partyId,
        amount: const Money.rupees(100),
        mode: 'cash',
        paymentAccountId: cashAccountId,
      ),
    );

    await expectLater(
      voidDocument(actor, documentId: sale.documentId, reason: 'Wrong'),
      throwsA(isA<VoidRefused>()),
    );

    final second = await sell(onUdhaar: true);
    final voided = await voidDocument(
      actor,
      documentId: second.documentId,
      reason: 'Wrong',
    );
    final entry = await db
        .customSelect(
          'SELECT entry_no FROM journal_entries WHERE id = ?',
          variables: [Variable<String>(voided.reversingEntryId)],
        )
        .getSingle();

    // Three entries so far: two sales and one payment. The reversal is the
    // fourth, with no gap where the refused attempt was.
    expect(entry.read<String>('entry_no'), endsWith('00004'));
  });

  test('the void is recorded in the audit trail', () async {
    final sale = await sell();
    await voidDocument(
      actor,
      documentId: sale.documentId,
      reason: 'Wrong customer',
    );

    final audit = await db
        .customSelect(
          'SELECT entity_id, summary FROM audit_log '
          "WHERE action_code = 'DOCUMENT_VOIDED'",
        )
        .getSingle();

    expect(audit.read<String>('entity_id'), sale.documentId);
    expect(audit.read<String>('summary'), contains(sale.docNo));
    expect(audit.read<String>('summary'), contains('Wrong customer'));
  });
}
