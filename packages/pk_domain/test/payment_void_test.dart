import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// Cancelling a payment, and correcting an opening balance (M31), without a
/// database.
///
/// The writer tests prove the rows; these prove the arithmetic and, above
/// all, the refusals — each of which exists because cancelling that payment
/// would leave the shop's books disagreeing with the bank's or with a bill.
void main() {
  const builder = PaymentVoidBuilder();

  PaymentVoidPosting cancel(
    PostedPaymentSnapshot payment, {
    String reason = 'Typed 5,000 for 500',
  }) => builder.build(
    actor: _actor(),
    payment: payment,
    reason: reason,
    journalNumber: _number('JV-2627-00042'),
  );

  group('cancelling a payment', () {
    test('a receipt is mirrored and its bills are owed again', () {
      final posting = cancel(_receipt());

      // Dr Cash 5,000 / Cr Receivable 3,000 / Cr Advances 2,000, undone side
      // for side and dated today.
      final lines = posting.journal.lines;
      expect(lines[0].accountSystemKey, '#cash');
      expect(lines[0].credit, const Money.rupees(5000));
      expect(lines[1].debit, const Money.rupees(3000));
      expect(lines[1].partyId, 'party-1');
      expect(lines[2].debit, const Money.rupees(2000));
      expect(posting.journal.sourceType, 'reversal');
      expect(posting.journal.entryDateLocal, '2026-08-23');
      expect(posting.reversesEntryId, 'je-1');
      expect(posting.assertBalanced, returnsNormally);

      // The one bill it paid is owed again, by exactly what it put on it.
      final bill = posting.reopened.single;
      expect(bill.documentId, 'bill-1');
      expect(bill.paid, Money.zero);
      expect(bill.balance, const Money.rupees(3000));
      expect(posting.releasedAllocationIds, ['alloc-1']);
      expect(posting.auditSummary, contains('Typed 5,000 for 500'));
    });

    test('a cancellation has to say why', () {
      expect(
        () => cancel(_receipt(), reason: '  '),
        throwsA(isA<VoidRefused>()),
      );
    });

    test('money taken at the counter goes with its bill', () {
      expect(
        () => cancel(_receipt(mode: 'exact')),
        throwsA(
          isA<VoidRefused>().having(
            (e) => e.reason,
            'reason',
            contains('INV-2627-0001'),
          ),
        ),
      );
    });

    test('a cheque still in hand can be cancelled', () {
      final posting = cancel(
        _receipt(mode: 'fifo', cheque: true, status: 'pending'),
      );
      expect(posting.journal.lines.first.credit, const Money.rupees(5000));
    });

    test('a cheque at the bank, cleared or bounced cannot be', () {
      for (final (status, chequeStatus) in [
        ('pending', 'deposited'),
        ('cleared', 'cleared'),
        ('bounced', 'bounced'),
      ]) {
        expect(
          () => cancel(
            _receipt(cheque: true, status: status, chequeStatus: chequeStatus),
          ),
          throwsA(
            isA<VoidRefused>().having(
              (e) => e.reason,
              'reason',
              contains('004512'),
            ),
          ),
          reason: chequeStatus,
        );
      }
    });

    test('the page and the books agree on what can be cancelled', () {
      expect(
        paymentLockOf(
          status: 'cleared',
          mode: 'cash',
          chequeStatus: null,
          takenWithBill: false,
        ),
        PaymentLock.none,
      );
      expect(
        paymentLockOf(
          status: 'pending',
          mode: 'cheque',
          chequeStatus: 'deposited',
          takenWithBill: false,
        ),
        PaymentLock.chequeAtBank,
      );
      expect(
        paymentLockOf(
          status: 'void',
          mode: 'cash',
          chequeStatus: null,
          takenWithBill: true,
        ),
        PaymentLock.cancelled,
      );
    });

    test('a payment already cancelled is not cancelled twice', () {
      expect(
        () => cancel(_receipt(status: 'void')),
        throwsA(isA<VoidRefused>()),
      );
    });
  });

  group('correcting an opening balance', () {
    test('the old opening is mirrored and the new figure is carried', () {
      final posting = const OpeningCorrectionBuilder().build(
        actor: _actor(),
        snapshot: OpeningSnapshot(
          partyId: 'party-1',
          partyName: 'Rashid Traders',
          opening: const Money.rupees(4500),
          entries: [OpeningEntrySnapshot(entryId: 'je-0', entry: _opening())],
        ),
        opening: const Money.rupees(45000),
        reason: 'A nought was dropped',
        journalNumbers: [_number('JV-2627-00043')],
      );

      final reversal = posting.reversals.single;
      expect(reversal.reversesEntryId, 'je-0');
      expect(reversal.journal.lines[0].credit, const Money.rupees(4500));
      expect(reversal.journal.lines[1].debit, const Money.rupees(4500));
      expect(posting.was, const Money.rupees(4500));
      expect(posting.now, const Money.rupees(45000));
    });

    test('the same figure again is not a correction', () {
      expect(
        () => const OpeningCorrectionBuilder().build(
          actor: _actor(),
          snapshot: const OpeningSnapshot(
            partyId: 'party-1',
            partyName: 'Rashid Traders',
            opening: Money.rupees(4500),
            entries: [],
          ),
          opening: const Money.rupees(4500),
          reason: 'Checking',
          journalNumbers: const [],
        ),
        throwsA(isA<VoidRefused>()),
      );
    });
  });
}

/// Rs 5,000 taken from Rashid: Rs 3,000 on one bill, Rs 2,000 left on
/// account.
PostedPaymentSnapshot _receipt({
  String mode = 'fifo',
  bool cheque = false,
  String status = 'cleared',
  String? chequeStatus,
}) => PostedPaymentSnapshot(
  paymentId: 'pay-1',
  paymentNo: 'RCP-2627-0001',
  direction: 'in',
  partyId: 'party-1',
  amount: const Money.rupees(5000),
  mode: cheque ? 'cheque' : 'cash',
  status: status,
  chequeNo: cheque ? '004512' : null,
  chequeStatus: cheque ? (chequeStatus ?? 'issued') : null,
  entryId: 'je-1',
  entry: JournalEntryPosting(
    entryNo: 'JV-2627-00007',
    entryDateUtcMillis: 0,
    entryDateLocal: '2026-08-20',
    fiscalYear: 2627,
    sourceType: 'payment',
    totalDebit: const Money.rupees(5000),
    totalCredit: const Money.rupees(5000),
    lines: [
      JournalLinePosting(
        lineNo: 1,
        accountSystemKey: cheque ? '#cheques' : '#cash',
        debit: const Money.rupees(5000),
        credit: Money.zero,
      ),
      const JournalLinePosting(
        lineNo: 2,
        accountSystemKey: '#receivable',
        debit: Money.zero,
        credit: Money.rupees(3000),
        partyId: 'party-1',
      ),
      const JournalLinePosting(
        lineNo: 3,
        accountSystemKey: '#advances',
        debit: Money.zero,
        credit: Money.rupees(2000),
        partyId: 'party-1',
      ),
    ],
  ),
  allocations: [
    PaymentAllocationSnapshot(
      allocationId: 'alloc-1',
      documentId: 'bill-1',
      docNo: 'INV-2627-0001',
      amount: const Money.rupees(3000),
      mode: mode,
      billPaid: const Money.rupees(3000),
      billBalance: Money.zero,
    ),
  ],
);

JournalEntryPosting _opening() => const JournalEntryPosting(
  entryNo: 'JV-2627-00001',
  entryDateUtcMillis: 0,
  entryDateLocal: '2026-07-01',
  fiscalYear: 2627,
  sourceType: 'opening',
  totalDebit: Money.rupees(4500),
  totalCredit: Money.rupees(4500),
  lines: [
    JournalLinePosting(
      lineNo: 1,
      accountSystemKey: '#receivable',
      debit: Money.rupees(4500),
      credit: Money.zero,
      partyId: 'party-1',
    ),
    JournalLinePosting(
      lineNo: 2,
      accountSystemKey: '#opening',
      debit: Money.zero,
      credit: Money.rupees(4500),
    ),
  ],
);

ActorContext _actor() => ActorContext(
  firmId: 'firm-1',
  userId: 'user-1',
  deviceId: 'device-1',
  startedAtUtc: DateTime.utc(2026, 8, 23, 9, 15),
);

AllocatedNumber _number(String formatted) =>
    AllocatedNumber(formatted: formatted, series: 'JV', sequence: 42);
