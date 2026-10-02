import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// Putting right what was keyed in (M31), against a real database.
///
/// The builder tests prove the arithmetic. These prove what a shopkeeper
/// would check: that a cancelled receipt puts the udhaar back, that an
/// edited one leaves one payment standing and not two, that a failed edit
/// leaves the original exactly where it was, that the books balance after
/// every one of them — and that a sale bill can never be reached this way.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late TxRunner runner;
  late DriftAppQueries queries;
  late PostSaleUseCase sell;
  late RecordReceiptUseCase receive;
  late RecordPurchaseUseCase buy;
  late PaySupplierUseCase pay;
  late RecordExpenseUseCase spend;
  late RecordDebitNoteUseCase charge;
  late VoidDocumentUseCase voidDocument;
  late MoveChequeUseCase cheques;
  late CorrectEntriesUseCase correct;
  late ActorContext actor;
  late String pcsUnitId;
  late String riceId;
  late String rashidId;
  late String millId;
  late String cashAccountId;
  late String chequeAccountId;

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 8, 23, 9, 15));
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
    queries = DriftAppQueries(db);
    sell = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));
    receive = RecordReceiptUseCase(writer: DriftPaymentWriter(runner: runner));
    buy = RecordPurchaseUseCase(writer: DriftPurchaseWriter(runner: runner));
    pay = PaySupplierUseCase(writer: DriftPaymentWriter(runner: runner));
    spend = RecordExpenseUseCase(writer: DriftExpenseWriter(runner: runner));
    charge = RecordDebitNoteUseCase(
      writer: DriftDebitNoteWriter(runner: runner),
    );
    voidDocument = VoidDocumentUseCase(writer: DriftVoidWriter(runner: runner));
    cheques = MoveChequeUseCase(writer: DriftChequeWriter(runner: runner));
    correct = CorrectEntriesUseCase(
      writer: DriftCorrectionWriter(runner: runner),
    );

    pcsUnitId =
        (await db.customSelect("SELECT id FROM units WHERE code = 'pcs'").get())
            .first
            .read<String>('id');
    final accounts = await queries.paymentAccounts(firm.firmId);
    cashAccountId = accounts.firstWhere((a) => a.isDefault).id;
    chequeAccountId = accounts.firstWhere((a) => a.modeLabel == 'cheque').id;

    await runner.run(actor, (tx) async {
      rashidId = await tx.insert('parties', {
        'name': 'Rashid Traders',
        'name_search': 'rashid traders',
        'party_type': 'customer',
      });
      millId = await tx.insert('parties', {
        'name': 'Punjab Rice Mills',
        'name_search': 'punjab rice mills',
        'party_type': 'supplier',
      });
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

  SaleLineDraft rice(int qty) => SaleLineDraft(
    itemId: riceId,
    itemName: 'Chawal Basmati',
    qty: Qty.units(qty),
    baseQty: Qty.units(qty),
    unitId: pcsUnitId,
    unitCode: 'pcs',
    rate: Rate.rupees(100),
  );

  /// A bill of Rs [rupees] to Rashid, all of it on udhaar unless [paidNow].
  Future<PostedSale> udhaar(int rupees, {int paidNow = 0}) => sell(
    actor,
    SaleDraft(
      partyId: rashidId,
      lines: [rice(rupees ~/ 100)],
      tenders: [
        if (paidNow > 0)
          TenderDraft(
            paymentAccountId: cashAccountId,
            mode: 'cash',
            amount: Money.rupees(paidNow),
          ),
      ],
    ),
  );

  Future<RecordedReceipt> take(int rupees, {bool cheque = false}) => receive(
    actor,
    ReceiptDraft(
      partyId: rashidId,
      amount: Money.rupees(rupees),
      mode: cheque ? 'cheque' : 'cash',
      paymentAccountId: cheque ? chequeAccountId : cashAccountId,
      chequeNo: cheque ? '004512' : null,
      chequeDateUtcMillis: cheque
          ? chequeDueUtcMillis(actor.businessDate)
          : null,
    ),
  );

  Future<String> deliver(int rupees) async => (await buy(
    actor,
    PurchaseDraft(
      partyId: millId,
      lines: [
        PurchaseLineDraft(
          itemId: riceId,
          itemName: 'Chawal Basmati',
          qty: Qty.units(10),
          baseQty: Qty.units(10),
          unitId: pcsUnitId,
          unitCode: 'pcs',
          rate: Rate.rupees(rupees ~/ 10),
        ),
      ],
    ),
  )).documentId;

  Future<Money> owes() async =>
      (await queries.partyById(firm.firmId, rashidId))!.balance;

  Future<Money> payable() async =>
      (await queries.partyById(firm.firmId, millId))!.payable;

  Future<void> expectBooksBalance() async {
    final health = await db.checkHealth();
    expect(health.findings, isEmpty);
    final totals = await db
        .customSelect(
          'SELECT SUM(debit_paisa) AS dr, SUM(credit_paisa) AS cr '
          'FROM journal_lines',
        )
        .getSingle();
    expect(totals.read<int>('dr'), totals.read<int>('cr'));
  }

  Future<List<Map<String, Object?>>> rows(String sql) async => [
    for (final r in await db.customSelect(sql).get()) r.data,
  ];

  group('cancelling a payment', () {
    test('a cancelled receipt restores what the customer owes', () async {
      final bill = await udhaar(1000);
      final receipt = await take(1500);
      expect(await owes(), const Money.rupees(-500));

      final voided = await correct.cancelPayment(
        actor,
        paymentId: receipt.paymentId,
        reason: 'Counted twice',
      );

      // The udhaar is back, the advance is gone, and the bill reads owed.
      expect(await owes(), const Money.rupees(1000));
      final open = await queries.openBillsFor(firm.firmId, rashidId);
      expect(open.single.documentId, bill.documentId);
      expect(open.single.outstanding, const Money.rupees(1000));
      expect(voided.reopenedDocumentIds, [bill.documentId]);

      final payment = await rows('SELECT status FROM payments');
      expect(payment.single['status'], 'void');
      // Released, so a reprinted bill no longer lists it as money handed
      // over.
      final printed = await queries.receiptFor(firm.firmId, bill.documentId);
      expect(printed!.tenders, isEmpty);

      final reversal = await rows(
        'SELECT payment_id, reverses_entry_id FROM journal_entries '
        "WHERE source_type = 'reversal'",
      );
      expect(reversal.single['payment_id'], receipt.paymentId);
      expect(reversal.single['reverses_entry_id'], receipt.journalEntryId);
      await expectBooksBalance();

      // The page still says what it had settled, and why it went.
      final detail = await queries.paymentDetail(
        firm.firmId,
        receipt.paymentId,
      );
      expect(detail!.isCancelled, isTrue);
      expect(detail.cancelReason, 'Counted twice');
      // Who did it, and when, on both halves.
      expect(detail.cancelledBy, 'Malik Sahib');
      expect(detail.cancelledAt, isNotNull);
      expect(detail.enteredBy, 'Malik Sahib');
      expect(detail.enteredAt, isNotNull);
      expect(detail.settled.single.docNo, bill.docNo);
    });

    test('a payment to a supplier cancelled is owed again', () async {
      await deliver(5000);
      final paid = await pay(
        actor,
        SupplierPaymentDraft(
          partyId: millId,
          amount: const Money.rupees(3000),
          mode: 'cash',
          paymentAccountId: cashAccountId,
        ),
      );
      expect(await payable(), const Money.rupees(2000));

      await correct.cancelPayment(
        actor,
        paymentId: paid.paymentId,
        reason: 'Paid from the wrong drawer',
      );

      expect(await payable(), const Money.rupees(5000));
      await expectBooksBalance();
    });

    test('money taken at the counter goes with its bill', () async {
      final bill = await udhaar(1000, paidNow: 400);
      final tender = await rows('SELECT id FROM payments');

      await expectLater(
        correct.cancelPayment(
          actor,
          paymentId: tender.single['id']! as String,
          reason: 'Wrong',
        ),
        throwsA(
          isA<VoidRefused>().having(
            (e) => e.reason,
            'reason',
            contains(bill.docNo),
          ),
        ),
      );
      expect(
        (await rows('SELECT status FROM payments')).single['status'],
        'cleared',
      );
    });

    test('a cheque in hand can be cancelled, one at the bank cannot', () async {
      await udhaar(1000);
      final inHand = await take(600, cheque: true);
      await correct.cancelPayment(
        actor,
        paymentId: inHand.paymentId,
        reason: 'Customer took the cheque back',
      );
      expect(await queries.chequesInHand(firm.firmId), isEmpty);
      expect(await owes(), const Money.rupees(1000));

      final atBank = await take(600, cheque: true);
      await cheques.deposit(actor, atBank.paymentId);
      await expectLater(
        correct.cancelPayment(
          actor,
          paymentId: atBank.paymentId,
          reason: 'Wrong',
        ),
        throwsA(
          isA<VoidRefused>().having(
            (e) => e.reason,
            'reason',
            contains('at the bank'),
          ),
        ),
      );
      expect(await owes(), const Money.rupees(400));
      await expectBooksBalance();
    });

    test(
      'a bill paid by a receipt says which receipt to cancel first',
      () async {
        final bill = await udhaar(1000);
        final receipt = await take(300);

        await expectLater(
          voidDocument(actor, documentId: bill.documentId, reason: 'Wrong'),
          throwsA(
            isA<VoidRefused>().having(
              (e) => e.reason,
              'reason',
              allOf(
                contains(receipt.paymentNo),
                contains('Cancel that payment'),
              ),
            ),
          ),
        );

        // And the advice now leads somewhere: cancel the receipt, then the bill.
        await correct.cancelPayment(
          actor,
          paymentId: receipt.paymentId,
          reason: 'Bill was wrong',
        );
        await voidDocument(actor, documentId: bill.documentId, reason: 'Wrong');
        expect(await owes(), Money.zero);
        await expectBooksBalance();
      },
    );
  });

  group('editing a payment', () {
    test(
      'an edited receipt leaves one live payment at the new amount',
      () async {
        final bill = await udhaar(3000);
        final wrong = await take(5000);

        final edited = await correct.editReceipt(
          actor,
          paymentId: wrong.paymentId,
          draft: ReceiptDraft(
            partyId: rashidId,
            amount: const Money.rupees(500),
            mode: 'cash',
            paymentAccountId: cashAccountId,
          ),
          reason: 'Typed 5,000 for 500',
        );

        final live = await rows(
          "SELECT id, amount_paisa FROM payments WHERE status <> 'void'",
        );
        expect(live.single['id'], edited.id);
        expect(live.single['amount_paisa'], 50000);
        expect(edited.cancelledNo, wrong.paymentNo);
        expect(await owes(), const Money.rupees(2500));
        final open = await queries.openBillsFor(firm.firmId, rashidId);
        expect(open.single.documentId, bill.documentId);
        expect(open.single.outstanding, const Money.rupees(2500));

        // The two halves are one act in the log.
        final link = await rows(
          'SELECT entity_id, summary FROM audit_log '
          "WHERE action_code = 'PAYMENT_EDITED'",
        );
        expect(link.single['entity_id'], edited.id);
        expect(link.single['summary'], contains(wrong.paymentNo));
        final detail = await queries.paymentDetail(firm.firmId, edited.id);
        expect(detail!.replaces, wrong.paymentNo);
        // And each opens the other: a chain an entry corrected twice can be
        // walked along.
        expect(detail.replacesId, wrong.paymentId);
        final old = await queries.paymentDetail(firm.firmId, wrong.paymentId);
        expect(old!.replacedBy, edited.no);
        expect(old.replacedById, edited.id);
        await expectBooksBalance();
      },
    );

    test('a failed edit leaves the original standing', () async {
      await deliver(5000);
      final paid = await pay(
        actor,
        SupplierPaymentDraft(
          partyId: millId,
          amount: const Money.rupees(3000),
          mode: 'cash',
          paymentAccountId: cashAccountId,
        ),
      );
      final entriesBefore = (await rows(
        'SELECT id FROM journal_entries',
      )).length;

      // More than was ever owed: the new payment is refused, and the
      // cancellation before it in the same transaction goes with it.
      await expectLater(
        correct.editSupplierPayment(
          actor,
          paymentId: paid.paymentId,
          draft: SupplierPaymentDraft(
            partyId: millId,
            amount: const Money.rupees(9000),
            mode: 'cash',
            paymentAccountId: cashAccountId,
          ),
          reason: 'Paid more',
        ),
        throwsA(isA<SupplierPaymentRefused>()),
      );

      final payment = await rows('SELECT status FROM payments');
      expect(payment.single['status'], 'cleared');
      expect(await payable(), const Money.rupees(2000));
      expect(
        (await rows('SELECT id FROM journal_entries')).length,
        entriesBefore,
      );
      expect(
        await rows(
          'SELECT id FROM payment_allocations WHERE deleted_at_utc IS NOT NULL',
        ),
        isEmpty,
      );
      await expectBooksBalance();
    });

    test(
      'a payment is corrected on its own khata, not moved to another',
      () async {
        await udhaar(1000);
        final receipt = await take(500);
        await expectLater(
          correct.editReceipt(
            actor,
            paymentId: receipt.paymentId,
            draft: ReceiptDraft(
              partyId: millId,
              amount: const Money.rupees(500),
              mode: 'cash',
              paymentAccountId: cashAccountId,
            ),
            reason: 'Wrong name',
          ),
          throwsA(isA<VoidRefused>()),
        );
        expect(await owes(), const Money.rupees(500));
      },
    );
  });

  group('charges and expenses', () {
    test('an expense is cancelled and leaves the books as they were', () async {
      final rent = await spend(
        actor,
        ExpenseDraft(
          accountSystemKey: 'rent',
          amount: const Money.rupees(4000),
          note: 'August rent',
          paymentAccountId: cashAccountId,
        ),
      );

      final detail = await queries.entryDocument(firm.firmId, rent.documentId);
      expect(detail!.head, 'rent');
      expect(detail.paidFromAccountId, cashAccountId);

      await correct.cancelExpense(
        actor,
        documentId: rent.documentId,
        reason: 'Entered twice',
      );
      expect(await queries.recentExpenses(firm.firmId), isEmpty);
      final byAccount = await rows(
        'SELECT account_id, SUM(debit_paisa - credit_paisa) AS net '
        'FROM journal_lines GROUP BY account_id',
      );
      for (final row in byAccount) {
        expect(row['net'], 0, reason: '${row['account_id']}');
      }
      await expectBooksBalance();
    });

    test('an expense is edited to the right amount', () async {
      final rent = await spend(
        actor,
        ExpenseDraft(
          accountSystemKey: 'rent',
          amount: const Money.rupees(40000),
          note: 'August rent',
          paymentAccountId: cashAccountId,
        ),
      );

      final edited = await correct.editExpense(
        actor,
        documentId: rent.documentId,
        draft: ExpenseDraft(
          accountSystemKey: 'rent',
          amount: const Money.rupees(4000),
          note: 'August rent',
          paymentAccountId: cashAccountId,
        ),
        reason: 'One nought too many',
      );

      final list = await queries.recentExpenses(firm.firmId);
      expect(list.single.id, edited.id);
      expect(list.single.amount, const Money.rupees(4000));
      expect(
        (await rows(
          "SELECT COUNT(*) AS n FROM audit_log WHERE action_code = 'EXPENSE_EDITED'",
        )).single['n'],
        1,
      );
      await expectBooksBalance();
    });

    test(
      'an expense a supplier has been paid against names the payment',
      () async {
        final freight = await spend(
          actor,
          ExpenseDraft(
            accountSystemKey: 'freight',
            amount: const Money.rupees(1200),
            note: 'Bilty',
            partyId: millId,
          ),
        );
        final paid = await pay(
          actor,
          SupplierPaymentDraft(
            partyId: millId,
            amount: const Money.rupees(1200),
            mode: 'cash',
            paymentAccountId: cashAccountId,
          ),
        );

        await expectLater(
          correct.cancelExpense(
            actor,
            documentId: freight.documentId,
            reason: 'Wrong',
          ),
          throwsA(
            isA<VoidRefused>().having(
              (e) => e.allocations,
              'allocations',
              contains(paid.paymentNo),
            ),
          ),
        );
      },
    );

    test('a charge is edited and the khata carries the new figure', () async {
      final note = await charge(
        actor,
        DebitNoteDraft(
          partyId: rashidId,
          amount: const Money.rupees(800),
          note: 'Bilty ka kiraya',
        ),
      );

      final edited = await correct.editCharge(
        actor,
        documentId: note.id,
        draft: DebitNoteDraft(
          partyId: rashidId,
          amount: const Money.rupees(500),
          note: 'Bilty ka kiraya',
        ),
        reason: 'Fare was 500',
      );

      expect(await owes(), const Money.rupees(500));
      expect(edited.cancelledNo, note.docNo);
      await expectBooksBalance();
    });

    test('a sale bill is never reached as a charge or an expense', () async {
      final bill = await udhaar(1000);
      for (final attempt in [
        () => correct.cancelCharge(
          actor,
          documentId: bill.documentId,
          reason: 'x',
        ),
        () => correct.cancelExpense(
          actor,
          documentId: bill.documentId,
          reason: 'x',
        ),
      ]) {
        await expectLater(attempt(), throwsA(isA<VoidRefused>()));
      }
      expect(
        await queries.documentStatus(firm.firmId, bill.documentId),
        'posted',
      );
    });
  });

  group('an opening balance', () {
    test('is corrected by reversing it and posting the new one', () async {
      final catalogue = DriftCatalogueWriter(runner);
      final aslam = await catalogue.addParty(
        actor,
        const PartyDraft(name: 'Aslam', openingBalance: Money.rupees(4500)),
      );

      await correct.correctOpening(
        actor,
        partyId: aslam,
        opening: const Money.rupees(45000),
        reason: 'A nought was dropped',
      );

      final party = await queries.partyById(firm.firmId, aslam);
      expect(party!.balance, const Money.rupees(45000));
      final receivable = await rows(
        'SELECT SUM(jl.debit_paisa - jl.credit_paisa) AS net '
        'FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
        "WHERE a.system_key = 'accounts_receivable' "
        "AND jl.party_id = '$aslam'",
      );
      expect(receivable.single['net'], 4500000);

      // Corrected twice, and to nothing: only the standing entry is undone.
      await correct.correctOpening(
        actor,
        partyId: aslam,
        opening: Money.zero,
        reason: 'They had paid it off before we started',
      );
      expect(
        (await queries.partyById(firm.firmId, aslam))!.balance,
        Money.zero,
      );
      final net = await rows(
        'SELECT SUM(jl.debit_paisa - jl.credit_paisa) AS net '
        'FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
        "WHERE a.system_key = 'accounts_receivable' "
        "AND jl.party_id = '$aslam'",
      );
      expect(net.single['net'], 0);
      // Nothing left for the start-up repair to post again.
      expect(await runner.run(actor, postMissingOpenings), 0);
      await expectBooksBalance();
    });
  });
}
