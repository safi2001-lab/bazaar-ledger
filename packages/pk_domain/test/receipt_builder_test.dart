import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// Taking money against udhaar, as rows, before any of them are written.
///
/// Every awkward case a shop actually produces, asserted with no database in
/// the way: a customer clearing three bills with one note, a customer paying
/// more than they owe, a cheque that is not money yet, and the arithmetic
/// that has to tie out to the paisa or the shop's cash and its khata disagree
/// by an amount nobody can account for.
void main() {
  const builder = ReceiptBuilder();

  ReceiptPosting build({
    Money amount = const Money.rupees(5000),
    List<OpenBill>? bills,
    String mode = 'cash',
    String? chequeNo,
  }) => builder.build(
    actor: _actor(),
    draft: ReceiptDraft(
      partyId: 'party-1',
      amount: amount,
      mode: mode,
      chequeNo: chequeNo,
      paymentAccountId: 'acct-cash',
    ),
    openBills:
        bills ??
        [_bill('a', '2026-06-01', 1, 3000), _bill('b', '2026-07-15', 2, 1500)],
    paymentNumber: _number('RCV-2627-0001'),
    journalNumber: _number('JV-2627-00001'),
    ledgerAccountId: 'ledger-cash',
  );

  group('the rows a receipt writes', () {
    test('one note clears the oldest bills and leaves the rest on account', () {
      final posting = build();

      expect(posting.allocations.map((a) => a.documentId), ['a', 'b']);
      expect(posting.allocations[0].amount, const Money.rupees(3000));
      expect(posting.allocations[1].amount, const Money.rupees(1500));
      expect(posting.unapplied, const Money.rupees(500));
    });

    test('each bill is told its new balance, not a delta', () {
      // A writer handed a delta has to read the row, add, and write it back,
      // and two tills doing that against one bill is a lost update. A writer
      // handed the answer cannot get it wrong.
      final posting = build(amount: const Money.rupees(3500));

      expect(posting.settlements, hasLength(2));
      expect(posting.settlements[0].balance, Money.zero);
      expect(posting.settlements[1].paid, const Money.rupees(500));
      expect(posting.settlements[1].balance, const Money.rupees(1000));
    });

    test('a payment that settles nothing still records the advance', () {
      final posting = build(amount: const Money.rupees(2000), bills: const []);

      expect(posting.allocations, isEmpty);
      expect(posting.unapplied, const Money.rupees(2000));
      expect(posting.payment.amount, const Money.rupees(2000));
    });

    test('the audit line says what happened in words', () {
      expect(
        build().auditSummary,
        allOf(
          contains('RCV-2627-0001'),
          contains('5,000.00'),
          contains('2 bill(s)'),
          contains('on account'),
        ),
      );
    });
  });

  group('the journal entry', () {
    test('debits the tender and credits receivables and advances', () {
      final lines = build().journal.lines;

      expect(lines, hasLength(3));
      expect(lines[0].accountSystemKey, '#ledger-cash');
      expect(lines[0].debit, const Money.rupees(5000));
      expect(lines[1].accountSystemKey, 'accounts_receivable');
      expect(lines[1].credit, const Money.rupees(4500));
      expect(lines[2].accountSystemKey, 'customer_advances');
      expect(lines[2].credit, const Money.rupees(500));
    });

    test('every line naming a party names it', () {
      // Without it a Trial Balance still balances and no report can say whose
      // udhaar moved — which is the only question the khata screen asks.
      final lines = build().journal.lines;

      expect(lines[1].partyId, 'party-1');
      expect(lines[2].partyId, 'party-1');
    });

    test('an advance is a liability, never a negative receivable', () {
      // Netting it against udhaar hides a real obligation inside an asset,
      // where a balance sheet cannot show it and an ageing report cannot find
      // it. The shop is holding the customer's money.
      final posting = build(amount: const Money.rupees(9000));
      final advance = posting.journal.lines.singleWhere(
        (l) => l.accountSystemKey == 'customer_advances',
      );

      expect(advance.credit, const Money.rupees(4500));
      expect(advance.debit, Money.zero);
      expect(posting.journal.lines.every((l) => !l.credit.isNegative), isTrue);
    });

    test('a cheque is not money in the bank until it clears', () {
      // The rule the sale path already follows. Debiting the bank here would
      // put a cheque that later bounces into the shop's bank balance, and the
      // shopkeeper would act on a number that is not theirs yet.
      final posting = build(mode: 'cheque', chequeNo: '000123');

      expect(posting.journal.lines[0].accountSystemKey, 'cheques_in_hand');
      expect(posting.payment.isCheque, isTrue);
    });

    test('no empty line is posted', () {
      // A customer paying exactly what they owe has no advance, and a zero
      // line is a claim that an account moved when it did not.
      final posting = build(amount: const Money.rupees(4500));

      expect(posting.journal.lines, hasLength(2));
      expect(
        posting.journal.lines.every(
          (l) => l.debit.isPositive || l.credit.isPositive,
        ),
        isTrue,
      );
    });

    test('the entry is stamped with the business date and fiscal year', () {
      final posting = build();

      expect(posting.journal.entryDateLocal, '2026-08-23');
      expect(posting.journal.fiscalYear, 2627);
      expect(posting.journal.sourceType, 'payment');
    });
  });

  group('what it refuses', () {
    test('a receipt of nothing', () {
      expect(() => build(amount: Money.zero), throwsA(isA<ArgumentError>()));
    });

    test('a cheque with no number', () {
      // The schema refuses this too. Caught here so the shopkeeper is told
      // which field is missing rather than shown a constraint name.
      expect(() => build(mode: 'cheque'), throwsA(isA<ArgumentError>()));
      expect(
        () => build(mode: 'cheque', chequeNo: '   '),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('the balance guarantee', () {
    test('debits equal credits, exactly', () {
      for (final amount in [1, 4499, 4500, 4501, 999999]) {
        final posting = build(amount: Money.paisa(amount));
        final debit = Money.sum([
          for (final l in posting.journal.lines) l.debit,
        ]);
        final credit = Money.sum([
          for (final l in posting.journal.lines) l.credit,
        ]);
        expect(debit, credit, reason: 'out by ${(debit - credit).amountOnly}');
      }
    });

    test('allocations plus the advance are the payment', () {
      // The check the journal cannot make for itself: both halves of a
      // balanced entry can come from the same wrong total.
      for (final amount in [1, 2999, 3000, 4500, 100000]) {
        final posting = build(amount: Money.paisa(amount));
        final allocated = Money.sum([
          for (final a in posting.allocations) a.amount,
        ]);
        expect(allocated + posting.unapplied, posting.payment.amount);
      }
    });

    test('a posting that does not tie out is refused, not written', () {
      // Built by hand, because the builder cannot produce one — which is the
      // point. This asserts the guard would catch a future builder that could.
      final broken = ReceiptPosting(
        payment: _payment(const Money.rupees(100)),
        allocations: const [
          AllocationPosting(
            documentId: 'a',
            amount: Money.rupees(40),
            mode: 'fifo',
          ),
        ],
        settlements: const [],
        unapplied: Money.zero,
        journal: JournalEntryPosting(
          entryNo: 'JV-1',
          entryDateUtcMillis: 0,
          entryDateLocal: '2026-08-23',
          fiscalYear: 2627,
          sourceType: 'payment',
          totalDebit: const Money.rupees(40),
          totalCredit: const Money.rupees(40),
          lines: const [
            JournalLinePosting(
              lineNo: 1,
              accountSystemKey: '#cash',
              debit: Money.rupees(40),
              credit: Money.zero,
            ),
            JournalLinePosting(
              lineNo: 2,
              accountSystemKey: 'accounts_receivable',
              debit: Money.zero,
              credit: Money.rupees(40),
            ),
          ],
        ),
        auditSummary: 'broken',
      );

      expect(broken.assertBalanced, throwsA(isA<StateError>()));
    });

    test('a negative amount is refused rather than balanced', () {
      // A negative debit is a credit wearing the wrong hat: the sums match,
      // the equality passes, and the schema refuses it three layers later as
      // a constraint error with nothing in it a shopkeeper could act on.
      final sneaky = ReceiptPosting(
        payment: _payment(Money.zero),
        allocations: const [],
        settlements: const [],
        unapplied: Money.zero,
        journal: JournalEntryPosting(
          entryNo: 'JV-1',
          entryDateUtcMillis: 0,
          entryDateLocal: '2026-08-23',
          fiscalYear: 2627,
          sourceType: 'payment',
          totalDebit: const Money.rupees(-10),
          totalCredit: const Money.rupees(-10),
          lines: const [
            JournalLinePosting(
              lineNo: 1,
              accountSystemKey: '#cash',
              debit: Money.rupees(-10),
              credit: Money.zero,
            ),
            JournalLinePosting(
              lineNo: 2,
              accountSystemKey: 'accounts_receivable',
              debit: Money.zero,
              credit: Money.rupees(-10),
            ),
          ],
        ),
        auditSummary: 'sneaky',
      );

      expect(sneaky.assertBalanced, throwsA(isA<StateError>()));
    });
  });
}

ActorContext _actor() => ActorContext(
  firmId: 'firm-1',
  userId: 'user-1',
  deviceId: 'device-1',
  // 2:15pm in Lahore on 23 August 2026, mid FY 2026-27.
  startedAtUtc: DateTime.utc(2026, 8, 23, 9, 15),
);

AllocatedNumber _number(String formatted) => AllocatedNumber(
  formatted: formatted,
  series: formatted.split('-').first,
  sequence: 1,
);

OpenBill _bill(String id, String date, int sequence, int rupees) => OpenBill(
  documentId: id,
  dateLocal: date,
  sequence: sequence,
  outstanding: Money.rupees(rupees),
);

PaymentPosting _payment(Money amount) => PaymentPosting(
  paymentNo: 'RCV-1',
  direction: 'in',
  paymentAccountId: 'acct',
  ledgerAccountId: 'cash',
  mode: 'cash',
  amount: amount,
  change: Money.zero,
  paymentDateUtcMillis: 0,
  paymentDateLocal: '2026-08-23',
);
