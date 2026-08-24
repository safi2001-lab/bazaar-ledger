import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// Money going out that is not stock.
///
/// A shop that records only what it sells and what it buys has a P&L that is
/// fiction: the cash book will not reconcile, the margin will look like
/// profit, and the shopkeeper will believe they made more than they did every
/// single month. The chart has carried these heads since M0 with nothing ever
/// posting to them.
void main() {
  const builder = ExpenseBuilder();

  ExpensePosting build({
    String head = 'utilities',
    Money amount = const Money.rupees(4000),
    String note = 'Bijli ka bill, August',
    String? paymentAccountId = 'acct-cash',
    String? partyId,
    String? ledgerAccountId = 'ledger-cash',
  }) => builder.build(
    actor: _actor(),
    draft: ExpenseDraft(
      accountSystemKey: head,
      amount: amount,
      note: note,
      paymentAccountId: paymentAccountId,
      partyId: partyId,
    ),
    expenseNumber: _number('EXP-2627-0001', 'EXP'),
    journalNumber: _number('JV-2627-00004', 'JV'),
    ledgerAccountId: ledgerAccountId,
  );

  group('a bill paid at the counter', () {
    test('debits the head and credits the drawer', () {
      final lines = build().journal.lines;

      expect(lines, hasLength(2));
      expect(lines[0].accountSystemKey, 'utilities');
      expect(lines[0].debit, const Money.rupees(4000));
      expect(lines[1].accountSystemKey, '#ledger-cash');
      expect(lines[1].credit, const Money.rupees(4000));
    });

    test('and the document says it is settled', () {
      final doc = build().document;

      expect(doc.docType, 'expense');
      expect(doc.total, const Money.rupees(4000));
      expect(doc.paid, const Money.rupees(4000));
      expect(doc.balance, Money.zero);
    });
  });

  group('a bill not paid yet', () {
    test('is owed to somebody by name', () {
      final posting = build(
        paymentAccountId: null,
        ledgerAccountId: null,
        partyId: 'landlord-1',
        head: 'rent',
      );

      final payable = posting.journal.lines.singleWhere(
        (l) => l.accountSystemKey == 'accounts_payable',
      );
      expect(payable.credit, const Money.rupees(4000));
      expect(payable.partyId, 'landlord-1');
      expect(posting.document.balance, const Money.rupees(4000));
    });
  });

  group('the head', () {
    test('is on the journal line, not on a column of its own', () {
      // A denormalised column would be a second answer to a question the
      // ledger already holds, and the two would disagree the first time one
      // was written by a path that forgot the other.
      final posting = build(head: 'salaries');

      expect(posting.journal.lines.first.accountSystemKey, 'salaries');
      expect(posting.headSystemKey, 'salaries');
    });

    test('is named by key, so renaming the account cannot break it', () {
      expect(build(head: 'rent').journal.lines.first.accountSystemKey, 'rent');
    });

    test('comes from a closed list', () {
      // Free-text heads produce "Bijli", "bijli", "Electricity" and "Light
      // bill" as four separate lines that add up to nothing anybody can read.
      expect(() => build(head: 'chai-pani'), throwsA(isA<ExpenseRefused>()));
      for (final head in expenseHeads) {
        expect(build(head: head).headSystemKey, head);
      }
    });
  });

  group('what it refuses', () {
    test('an expense of nothing', () {
      expect(() => build(amount: Money.zero), throwsA(isA<ExpenseRefused>()));
      expect(
        () => build(amount: const Money.rupees(-1)),
        throwsA(isA<ExpenseRefused>()),
      );
    });

    test('an expense with no note', () {
      // "Misc — Rs 4,000" six months later is a number nobody can defend, and
      // misc is where every unlabelled expense ends up.
      expect(() => build(note: '   '), throwsA(isA<ExpenseRefused>()));
    });

    test('money paid with no account it came out of', () {
      expect(
        () => build(ledgerAccountId: null),
        throwsA(isA<ExpenseRefused>()),
      );
    });

    test('an unpaid expense with nobody to pay', () {
      // Money the shop can never settle, sitting in a total it can never
      // explain. The mirror of a bill left part-paid having to name a
      // customer.
      expect(
        () => build(paymentAccountId: null, ledgerAccountId: null),
        throwsA(isA<ExpenseRefused>()),
      );
    });
  });

  group('the entry balances', () {
    test('paid and unpaid alike', () {
      for (final amount in [1, 999, 400000]) {
        for (final paid in [true, false]) {
          final posting = build(
            amount: Money.paisa(amount),
            paymentAccountId: paid ? 'acct-cash' : null,
            ledgerAccountId: paid ? 'ledger-cash' : null,
            partyId: paid ? null : 'landlord-1',
          );
          expect(
            Money.sum([for (final l in posting.journal.lines) l.debit]),
            Money.sum([for (final l in posting.journal.lines) l.credit]),
          );
        }
      }
    });

    test('and the audit line says head, amount and what it was for', () {
      final summary = build(note: 'Bijli ka bill, August').auditSummary;

      expect(summary, contains('EXP-2627-0001'));
      expect(summary, contains('utilities'));
      expect(summary, contains('4,000.00'));
      expect(summary, contains('Bijli ka bill, August'));
    });
  });
}

ActorContext _actor() => ActorContext(
  firmId: 'firm-1',
  userId: 'user-1',
  deviceId: 'device-1',
  startedAtUtc: DateTime.utc(2026, 8, 23, 9, 15),
);

AllocatedNumber _number(String formatted, String series) =>
    AllocatedNumber(formatted: formatted, series: series, sequence: 1);
