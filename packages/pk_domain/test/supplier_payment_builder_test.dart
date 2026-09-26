import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// Paying a supplier, as rows, before any of them are written.
///
/// The receipt turned around. The same oldest-first allocation, the same
/// absolute settlements, and one rule that goes the other way on purpose:
/// the shop paying more than it owes is refused, because the money the
/// supplier would then owe back is an asset this chart has no account for.
void main() {
  const builder = SupplierPaymentBuilder();

  ReceiptPosting build({
    Money amount = const Money.rupees(4000),
    List<OpenBill>? bills,
    String mode = 'cash',
  }) => builder.build(
    actor: _actor(),
    draft: SupplierPaymentDraft(
      partyId: 'mill-1',
      amount: amount,
      mode: mode,
      paymentAccountId: 'acct-cash',
    ),
    openBills:
        bills ??
        [
          _bill('pur-b', '2026-07-15', 2, 2500),
          _bill('pur-a', '2026-06-01', 1, 3000),
        ],
    paymentNumber: _number('PAY-2627-0001'),
    journalNumber: _number('JV-2627-00001'),
    ledgerAccountId: 'ledger-cash',
  );

  group('which deliveries a payment settles', () {
    test(
      'the oldest delivery is paid first, whatever order they arrive in',
      () {
        final posting = build();

        expect(posting.allocations.map((a) => a.documentId), [
          'pur-a',
          'pur-b',
        ]);
        expect(posting.allocations[0].amount, const Money.rupees(3000));
        expect(posting.allocations[1].amount, const Money.rupees(1000));
      },
    );

    test('each delivery is told its new balance, not a delta', () {
      final posting = build();

      expect(posting.settlements[0].balance, Money.zero);
      expect(posting.settlements[1].paid, const Money.rupees(1000));
      expect(posting.settlements[1].balance, const Money.rupees(1500));
    });

    test('nothing is ever left over as an advance', () {
      final posting = build(amount: const Money.rupees(5500));

      expect(posting.unapplied, Money.zero);
      expect(
        Money.sum([for (final a in posting.allocations) a.amount]),
        const Money.rupees(5500),
      );
    });
  });

  group('the journal entry a payment writes', () {
    test(
      'debits the payable by name and credits where the money came from',
      () {
        final lines = build().journal.lines;

        expect(lines, hasLength(2));
        expect(lines[0].accountSystemKey, 'accounts_payable');
        expect(lines[0].debit, const Money.rupees(4000));
        expect(lines[0].partyId, 'mill-1');
        expect(lines[1].accountSystemKey, '#ledger-cash');
        expect(lines[1].credit, const Money.rupees(4000));
      },
    );

    test('the payment is money going out', () {
      final payment = build().payment;

      expect(payment.direction, 'out');
      expect(payment.partyId, 'mill-1');
      expect(payment.amount, const Money.rupees(4000));
    });

    test('debits equal credits, exactly', () {
      final journal = build(amount: const Money.paisa(123457)).journal;

      expect(
        Money.sum([for (final l in journal.lines) l.debit]),
        Money.sum([for (final l in journal.lines) l.credit]),
      );
      expect(journal.totalDebit, const Money.paisa(123457));
    });
  });

  group('what a supplier payment refuses', () {
    test('a payment of nothing', () {
      expect(
        () => build(amount: Money.zero),
        throwsA(isA<SupplierPaymentRefused>()),
      );
    });

    test('paying more than is owed', () {
      // Money beyond the bills is an advance the supplier owes back — an
      // asset. Crediting it to the payable would hide it inside a liability,
      // which is the netting the receipt side was built to avoid.
      expect(
        () => build(amount: const Money.rupees(5501)),
        throwsA(
          isA<SupplierPaymentRefused>().having(
            (e) => e.reason,
            'reason',
            contains('5,500'),
          ),
        ),
      );
    });

    test('paying a supplier who is owed nothing', () {
      expect(
        () => build(bills: const []),
        throwsA(isA<SupplierPaymentRefused>()),
      );
    });

    test('a cheque, which belongs to the post-dated cheque book', () {
      expect(
        () => build(mode: 'cheque'),
        throwsA(isA<SupplierPaymentRefused>()),
      );
    });
  });
}

ActorContext _actor() => ActorContext(
  firmId: 'firm-1',
  userId: 'user-1',
  deviceId: 'device-1',
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
