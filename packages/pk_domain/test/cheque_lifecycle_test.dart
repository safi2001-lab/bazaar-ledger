import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// A cheque's life after it is taken: to the bank, cleared, or bounced.
void main() {
  const lifecycle = ChequeLifecycle();

  ActorContext on(String date) => ActorContext(
    firmId: 'F1',
    userId: 'U1',
    deviceId: 'D1',
    // 14:15 PKT on the given day.
    startedAtUtc: DateTime.parse('${date}T09:15:00Z'),
  );

  ChequeInHand cheque({String? due = '2026-10-15', bool deposited = false}) =>
      ChequeInHand(
        paymentId: 'PAY-1',
        paymentNo: 'RCV-2627-0007',
        partyId: 'P-RASHID',
        partyName: 'Rashid Traders',
        amount: const Money.rupees(50000),
        chequeNo: '004512',
        bank: 'Meezan',
        due: due == null ? null : BusinessDate(due),
        receivedOn: const BusinessDate('2026-09-15'),
        deposited: deposited,
      );

  const journalNo = AllocatedNumber(
    formatted: 'JV-2627-00042',
    series: 'JV',
    sequence: 42,
  );

  Money side(ChequeStepPosting p, String key, {bool debit = true}) =>
      Money.sum([
        for (final l in p.journal!.lines)
          if (l.accountSystemKey == key) debit ? l.debit : l.credit,
      ]);

  group('taken to the bank', () {
    test('moves no money, only where the cheque is', () {
      final step = lifecycle.deposit(actor: on('2026-10-15'), cheque: cheque());

      expect(step.journal, isNull);
      expect(step.chequeStatus, 'deposited');
      expect(step.paymentStatus, 'pending');
    });

    test('is refused before its date, because no bank will take it', () {
      expect(
        () => lifecycle.deposit(actor: on('2026-10-14'), cheque: cheque()),
        throwsA(
          isA<ChequeRefused>().having(
            (e) => e.reason,
            'reason',
            contains('2026-10-15'),
          ),
        ),
      );
    });

    test('a cheque with no recorded date is not stranded', () {
      expect(
        lifecycle
            .deposit(actor: on('2026-09-20'), cheque: cheque(due: null))
            .chequeStatus,
        'deposited',
      );
    });
  });

  group('cleared', () {
    test('the money moves from Cheques in Hand into the bank', () {
      final step = lifecycle.clear(
        actor: on('2026-10-16'),
        cheque: cheque(deposited: true),
        bankLedgerAccountId: 'ACC-BANK',
        journalNumber: journalNo,
      );

      expect(side(step, '#ACC-BANK'), const Money.rupees(50000));
      expect(
        side(step, 'cheques_in_hand', debit: false),
        const Money.rupees(50000),
      );
      expect(step.paymentStatus, 'cleared');
      step.assertBalanced();
    });

    test('is refused before its date', () {
      expect(
        () => lifecycle.clear(
          actor: on('2026-10-01'),
          cheque: cheque(),
          bankLedgerAccountId: 'ACC-BANK',
          journalNumber: journalNo,
        ),
        throwsA(isA<ChequeRefused>()),
      );
    });
  });

  group('bounced', () {
    ChequeStepPosting bounce({
      List<ChequeAllocation>? allocations,
    }) => lifecycle.bounce(
      actor: on('2026-10-18'),
      cheque: cheque(deposited: true),
      allocations:
          allocations ??
          const [
            ChequeAllocation(documentId: 'INV-A', amount: Money.rupees(30000)),
            ChequeAllocation(documentId: 'INV-B', amount: Money.rupees(15000)),
          ],
      bills: {
        'INV-A': (paid: const Money.rupees(30000), balance: Money.zero),
        'INV-B': (
          paid: const Money.rupees(15000),
          balance: const Money.rupees(5000),
        ),
      },
      journalNumber: journalNo,
      reason: 'Insufficient funds',
    );

    test('the bills it paid are owed again, for exactly what it paid', () {
      final step = bounce();

      expect(step.reopened.map((r) => r.documentId), ['INV-A', 'INV-B']);
      expect(step.reopened[0].paid, Money.zero);
      expect(step.reopened[0].balance, const Money.rupees(30000));
      expect(step.reopened[1].balance, const Money.rupees(20000));
    });

    test('the udhaar comes back by name, and the advance is withdrawn', () {
      // Rs 45,000 went on bills and Rs 5,000 was left as an advance. Both
      // were only ever as real as the cheque.
      final step = bounce();

      expect(side(step, 'accounts_receivable'), const Money.rupees(45000));
      expect(side(step, 'customer_advances'), const Money.rupees(5000));
      expect(
        side(step, 'cheques_in_hand', debit: false),
        const Money.rupees(50000),
      );
      expect(
        step.journal!.lines.where((l) => l.partyId == 'P-RASHID'),
        hasLength(3),
      );
      step.assertBalanced();
    });

    test('the 489-F notice date is thirty days from the bounce', () {
      final step = bounce();

      expect(step.auditSummary, contains('489-F notice by 2026-11-17'));
      expect(step.journal!.sourceType, 'reversal');
    });

    test('a cheque allocated beyond its amount is a corrupt record', () {
      expect(
        () => bounce(
          allocations: const [
            ChequeAllocation(documentId: 'INV-A', amount: Money.rupees(60000)),
          ],
        ),
        throwsStateError,
      );
    });
  });
}
