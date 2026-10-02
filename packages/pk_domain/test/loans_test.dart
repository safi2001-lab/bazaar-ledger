import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// Loans the shop has taken, their repayments, and a statement for each
/// (M48), as pure rules: no database, every figure exact to the paisa.
void main() {
  const today = BusinessDate('2026-10-02');

  LoanDraft loan({
    String lender = 'Meezan Bank',
    int rupees = 500000,
    int feeRupees = 0,
    String takenOn = '2026-07-01',
  }) => LoanDraft(
    lender: lender,
    amount: Money.rupees(rupees),
    fee: Money.rupees(feeRupees),
    intoPaymentAccountId: 'bank-pa',
    takenOn: BusinessDate(takenOn),
    rateBp: 1800,
  );

  JournalEntryPosting taken(LoanDraft draft) => loanTakenEntry(
    draft: draft,
    today: today,
    loanName: 'Loan from Meezan Bank',
    entryNo: 'JV-2627-00001',
    recordedAtUtcMillis: 0,
    loanAccountId: 'loan',
    intoAccountId: 'bank',
    feeAccountId: 'fee',
  );

  JournalEntryPosting repaid({
    required int paid,
    int interest = 0,
    int charges = 0,
    int owed = 500000,
    String on = '2026-08-01',
  }) => repaymentEntry(
    draft: RepaymentDraft(
      loanId: 'loan',
      paid: Money.rupees(paid),
      interest: Money.rupees(interest),
      charges: Money.rupees(charges),
      fromPaymentAccountId: 'bank-pa',
      paidOn: BusinessDate(on),
    ),
    loanName: 'Loan from Meezan Bank',
    owed: Money.rupees(owed),
    takenOn: const BusinessDate('2026-07-01'),
    today: today,
    entryNo: 'JV-2627-00002',
    recordedAtUtcMillis: 0,
    loanAccountId: 'loan',
    fromAccountId: 'bank',
    interestAccountId: 'interest',
    chargesAccountId: 'charges',
  );

  Money side(JournalEntryPosting e, String account, {bool debit = true}) =>
      Money.sum([
        for (final l in e.lines)
          if (l.accountSystemKey == '#$account') debit ? l.debit : l.credit,
      ]);

  group('loans', () {
    test('a loan with a fee brings in the amount less the fee, and is owed '
        'in full', () {
      final entry = taken(loan(feeRupees: 5000));

      expect(side(entry, 'bank'), const Money.rupees(495000));
      expect(side(entry, 'fee'), const Money.rupees(5000));
      expect(side(entry, 'loan', debit: false), const Money.rupees(500000));
      expect(entry.totalDebit, entry.totalCredit);
      expect(entry.entryDateLocal, '2026-07-01');
      expect(entry.fiscalYear, 2627);
    });

    test('a repayment takes principal off the loan and books interest and '
        'charges as costs', () {
      final entry = repaid(paid: 20000, interest: 7397, charges: 500);

      expect(side(entry, 'loan'), const Money.rupees(12103));
      expect(side(entry, 'interest'), const Money.rupees(7397));
      expect(side(entry, 'charges'), const Money.rupees(500));
      expect(side(entry, 'bank', debit: false), const Money.rupees(20000));
      expect(entry.totalDebit, const Money.rupees(20000));
    });

    test('more off the loan than is owed is refused in words', () {
      expect(
        () => repaid(paid: 60000, owed: 50000),
        throwsA(
          isA<LoanRefused>().having(
            (r) => r.reason,
            'reason',
            contains('more than the Rs 50,000.00 still owed'),
          ),
        ),
      );
      // The whole of it as interest is not over the loan.
      expect(
        () => repaid(paid: 60000, interest: 10000, owed: 50000),
        returnsNormally,
      );
    });

    test('interest and charges more than was paid are refused', () {
      expect(
        () => repaid(paid: 1000, interest: 900, charges: 200),
        throwsA(isA<LoanRefused>()),
      );
      expect(() => repaid(paid: 0), throwsA(isA<LoanRefused>()));
      expect(
        () => repaid(paid: 1000, on: '2026-06-30'),
        throwsA(isA<LoanRefused>()),
        reason: 'paid before the loan was taken',
      );
      expect(
        () => repaid(paid: 1000, on: '2026-10-03'),
        throwsA(isA<LoanRefused>()),
        reason: 'a day not yet come',
      );
    });

    test('a loan with no lender, a fee as large as it, or a day not yet '
        'come is refused', () {
      for (final bad in [
        loan(lender: '  '),
        loan(rupees: 0),
        loan(rupees: 5000, feeRupees: 5000),
        loan(takenOn: '2026-10-03'),
      ]) {
        expect(() => taken(bad), throwsA(isA<LoanRefused>()));
      }
    });

    test('interest is suggested at the rate for the days since the loan '
        'was last paid', () {
      // Rs 5 lakh at 18% a year for 31 days: 500000 x 0.18 x 31 / 365.
      expect(
        suggestedInterest(
          owed: const Money.rupees(500000),
          rateBp: 1800,
          since: const BusinessDate('2026-07-01'),
          on: const BusinessDate('2026-08-01'),
        ),
        Money.parse('7643.84'),
      );
      expect(
        suggestedInterest(
          owed: const Money.rupees(500000),
          rateBp: 1800,
          since: const BusinessDate('2026-08-01'),
          on: const BusinessDate('2026-08-01'),
        ),
        Money.zero,
      );
      final runs = interestRunsFrom([
        _posting('a', '2026-07-01', credit: 500000),
        _posting('b', '2026-08-01', debit: 10000),
        // Cancelled, and its cancellation: neither restarts the clock.
        _posting('c', '2026-09-01', debit: 10000, reversed: true),
        _posting('d', '2026-09-20', credit: 10000, reverses: 'c'),
      ], const BusinessDate('2026-10-01'));
      expect(runs, const BusinessDate('2026-08-01'));
    });

    test('terms are kept and read back as they were', () {
      final terms = LoanTerms(
        lender: 'Bhai Jan',
        amount: const Money.rupees(50000),
        takenOn: const BusinessDate('2026-09-01'),
        receiptEntryId: 'je-1',
        rateBp: 1650,
        termMonths: 10,
        instalment: const Money.rupees(5000),
        notes: 'Eid stock',
      );
      final back = LoanTerms.fromJson(terms.toJson())!;
      expect(back.lender, 'Bhai Jan');
      expect(back.amount, const Money.rupees(50000));
      expect(back.rateBp, 1650);
      expect(back.termMonths, 10);
      expect(back.instalment, const Money.rupees(5000));
      expect(back.notes, 'Eid stock');
      expect(LoanTerms.fromJson('not json'), isNull);
    });

    test('a loan cannot be cancelled while repayments stand', () {
      final receipt = _posting('a', '2026-07-01', credit: 500000);
      expect(
        () => checkLoanCancel(
          entry: receipt,
          owedNow: const Money.rupees(400000),
          reason: 'Entered twice',
        ),
        throwsA(isA<LoanRefused>()),
      );
      expect(
        () => checkLoanCancel(
          entry: receipt,
          owedNow: const Money.rupees(500000),
          reason: '  ',
        ),
        throwsA(isA<LoanRefused>()),
        reason: 'a cancellation says why',
      );
      expect(
        () => checkLoanCancel(
          entry: receipt,
          owedNow: const Money.rupees(500000),
          reason: 'Entered twice',
        ),
        returnsNormally,
      );
    });
  });

  group('loan statement', () {
    final postings = [
      _posting('a', '2026-07-01', credit: 500000, charges: 5000),
      _posting('b', '2026-08-01', debit: 12357, interest: 7643),
      _posting('c', '2026-09-01', debit: 12357, interest: 7643, reversed: true),
      _posting(
        'd',
        '2026-09-02',
        credit: 12357,
        interest: -7643,
        reverses: 'c',
      ),
      // A month of interest only: nothing off the loan.
      _posting('e', '2026-09-30', interest: 7400),
    ];

    test('opens on what was owed before, and closes on what is owed at the '
        'end', () {
      final st = buildLoanStatement(
        name: 'Loan from Meezan Bank',
        postings: postings,
        from: const BusinessDate('2026-08-01'),
        to: const BusinessDate('2026-09-30'),
      );
      expect(st.opening, const Money.rupees(500000));
      expect(st.lines, hasLength(4));
      expect(st.closing, const Money.rupees(487643));
      expect(st.closing, st.opening + st.borrowed - st.repaid);
      expect(st.interest, const Money.rupees(7643 + 7400));
    });

    test('a cancelled repayment is a minus in the column it was in', () {
      final st = buildLoanStatement(
        name: 'Loan from Meezan Bank',
        postings: postings,
        from: const BusinessDate('2026-07-01'),
        to: const BusinessDate('2026-10-02'),
      );
      final cancelled = st.lines.firstWhere((l) => l.entryId == 'd');
      expect(cancelled.kind, LoanLineKind.cancelled);
      expect(cancelled.borrowed, Money.zero);
      expect(cancelled.repaid, const Money.rupees(-12357));
      expect(cancelled.interest, const Money.rupees(-7643));
      expect(st.lines.firstWhere((l) => l.entryId == 'c').reversed, isTrue);
      expect(st.borrowed, const Money.rupees(500000));
      expect(st.repaid, const Money.rupees(12357));
      expect(st.charges, const Money.rupees(5000));

      final interestOnly = st.lines.last;
      expect(interestOnly.kind, LoanLineKind.repaid);
      expect(interestOnly.repaid, Money.zero);
      expect(interestOnly.owedAfter, const Money.rupees(487643));
    });

    test('a period with nothing in it still says what is owed', () {
      final st = buildLoanStatement(
        name: 'Loan from Meezan Bank',
        postings: postings,
        from: const BusinessDate('2026-10-01'),
        to: const BusinessDate('2026-10-31'),
      );
      expect(st.lines, isEmpty);
      expect(st.opening, const Money.rupees(487643));
      expect(st.closing, const Money.rupees(487643));
    });
  });
}

LoanPosting _posting(
  String id,
  String date, {
  int debit = 0,
  int credit = 0,
  int interest = 0,
  int charges = 0,
  bool reversed = false,
  String? reverses,
}) => LoanPosting(
  entryId: id,
  entryNo: 'JV-$id',
  date: BusinessDate(date),
  narration: id,
  loanDebit: Money.rupees(debit),
  loanCredit: Money.rupees(credit),
  interest: Money.rupees(interest),
  charges: Money.rupees(charges),
  reversed: reversed,
  reversesEntryId: reverses,
);
