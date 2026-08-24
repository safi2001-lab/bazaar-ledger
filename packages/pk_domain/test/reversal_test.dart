import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// Undoing a posted document without editing history.
///
/// A posted document is immutable, because the shopkeeper has already printed
/// it and handed the paper to a customer. A number that changes underneath
/// somebody holding the receipt is what makes them stop trusting the app.
void main() {
  const builder = VoidBuilder();

  VoidPosting build({
    String reason = 'Wrong customer',
    List<String> allocations = const [],
    JournalEntryPosting? entry,
    List<StockMovementPosting>? movements,
  }) => builder.build(
    actor: _actor(),
    documentId: 'doc-1',
    docNo: 'INV-2627-0001',
    reason: reason,
    originalEntry: entry ?? _saleEntry(),
    originalEntryId: 'je-1',
    originalMovements: movements ?? [_movement()],
    journalNumber: _number('JV-2627-00009'),
    allocatedPayments: allocations,
  );

  group('the sides swap', () {
    test('every debit becomes a credit and back', () {
      final lines = build().journal.lines;

      // The sale was Dr Cash 1000, Dr COGS 600, Cr Sales 1000, Cr Inventory
      // 600. Undoing it is the same four lines with the sides exchanged.
      expect(lines, hasLength(4));
      expect(lines[0].accountSystemKey, '#cash');
      expect(lines[0].debit, Money.zero);
      expect(lines[0].credit, const Money.rupees(1000));
      expect(lines[1].accountSystemKey, 'cogs');
      expect(lines[1].credit, const Money.rupees(600));
      expect(lines[2].accountSystemKey, 'sales');
      expect(lines[2].debit, const Money.rupees(1000));
      expect(lines[3].accountSystemKey, 'inventory');
      expect(lines[3].debit, const Money.rupees(600));
    });

    test('nothing is ever negated', () {
      // Negating looks equivalent and is not. A Trial Balance built by
      // summing a column cannot tell a negative debit from a credit, so the
      // report balances while the accounts are wrong.
      final posting = build();

      for (final line in posting.journal.lines) {
        expect(line.debit.isNegative, isFalse, reason: '${line.lineNo}');
        expect(line.credit.isNegative, isFalse, reason: '${line.lineNo}');
      }
      expect(posting.assertBalanced, returnsNormally);
    });

    test('and the totals swap with them', () {
      final entry = build().journal;

      expect(entry.totalDebit, const Money.rupees(1600));
      expect(entry.totalCredit, const Money.rupees(1600));
      expect(
        Money.sum([for (final l in entry.lines) l.debit]),
        entry.totalDebit,
      );
    });

    test('the party stays on the line it was on', () {
      // Otherwise the reversal balances and no report can say whose udhaar
      // came back, which is the same defect as the original entry not naming
      // them.
      final posting = build(entry: _udhaarEntry());
      final receivable = posting.journal.lines.singleWhere(
        (l) => l.accountSystemKey == 'accounts_receivable',
      );

      expect(receivable.partyId, 'party-1');
      expect(receivable.credit, const Money.rupees(1000));
    });
  });

  group('when it happened', () {
    test('the reversal is dated today, never backdated', () {
      // A reversal backdated into a period that has been closed, reported or
      // filed changes a number somebody has already acted on. Dated today it
      // nets to zero and leaves both halves visible, which is what a day book
      // should show.
      final posting = build(entry: _saleEntry(dateLocal: '2026-03-11'));

      expect(posting.journal.entryDateLocal, '2026-08-23');
      expect(posting.journal.fiscalYear, 2627);
    });

    test('and says what it undid, in its own narration', () {
      final entry = build(reason: 'Wrong customer').journal;

      expect(entry.narration, contains('INV-2627-0001'));
      expect(entry.narration, contains('JV-2627-00001'));
      expect(entry.narration, contains('Wrong customer'));
      expect(entry.sourceType, 'reversal');
    });

    test('and points at the entry it reverses', () {
      // A reversal that does not point at its original is a second entry
      // nobody can explain.
      expect(build().reversesEntryId, 'je-1');
    });
  });

  group('the stock goes back', () {
    test('at the cost it left at, not at today', () {
      // Putting the goods back at a cost they were never carried at would
      // change the shop's inventory value because somebody corrected a typo,
      // and the difference would land in no account at all.
      final posting = build();
      final movement = posting.stockMovements.single;

      expect(movement.qtyDelta.inThousandths, 2000);
      expect(movement.rate, const Rate.rupees(300));
      expect(movement.valueDelta, const Money.rupees(600));
    });

    test('as an adjustment, never as a return', () {
      // A return is a customer bringing goods back — a different event with
      // its own document and its own tax treatment. This is a bill that
      // should never have existed.
      expect(build().stockMovements.single.txnType, 'adjustment');
    });

    test('dated today, like the entry', () {
      expect(build().stockMovements.single.occurredOnLocal, '2026-08-23');
    });

    test('a document that moved no stock reverses none', () {
      // A payment, an expense, a quotation. The entry still reverses.
      final posting = build(movements: const []);

      expect(posting.stockMovements, isEmpty);
      expect(posting.journal.lines, isNotEmpty);
    });
  });

  group('what it refuses', () {
    test('a void with no reason', () {
      // A void with no reason is a hole in the numbering nobody can account
      // for six months later, and the first thing an auditor asks about.
      expect(() => build(reason: ''), throwsA(isA<VoidRefused>()));
      expect(() => build(reason: '   '), throwsA(isA<VoidRefused>()));
    });

    test('a bill that has been paid against', () {
      // The naive void leaves allocation rows pointing at a document no
      // report considers real, and findOverAllocatedPayments() cannot catch
      // it because the sum still fits. The customer's khata quietly gains
      // money nobody returned.
      expect(
        () => build(allocations: const ['RCV-2627-0004']),
        throwsA(isA<VoidRefused>()),
      );
    });

    test('and names the receipts standing in the way', () {
      // "Deal with the payments first" is only actionable if the shopkeeper
      // is told which.
      try {
        build(allocations: const ['RCV-2627-0004', 'RCV-2627-0011']);
        fail('the void was allowed');
      } on VoidRefused catch (refusal) {
        expect(refusal.allocations, hasLength(2));
        expect('$refusal', contains('RCV-2627-0004'));
        expect('$refusal', contains('RCV-2627-0011'));
      }
    });

    test('an entry with no lines, because nothing happened', () {
      expect(
        () => build(entry: _saleEntry(lines: const [])),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('the audit line', () {
    test('says what was voided and why, in words', () {
      final summary = build(reason: 'Customer changed their mind').auditSummary;

      expect(summary, contains('INV-2627-0001'));
      expect(summary, contains('Customer changed their mind'));
    });

    test('and the reason is trimmed rather than stored ragged', () {
      expect(build(reason: '  Duplicate  ').reason, 'Duplicate');
    });
  });
}

ActorContext _actor() => ActorContext(
  firmId: 'firm-1',
  userId: 'user-1',
  deviceId: 'device-1',
  startedAtUtc: DateTime.utc(2026, 8, 23, 9, 15),
);

AllocatedNumber _number(String formatted) =>
    AllocatedNumber(formatted: formatted, series: 'JV', sequence: 9);

/// A cash sale of Rs 1,000 on goods that cost Rs 600.
JournalEntryPosting _saleEntry({
  String dateLocal = '2026-08-23',
  List<JournalLinePosting>? lines,
}) => JournalEntryPosting(
  entryNo: 'JV-2627-00001',
  entryDateUtcMillis: 0,
  entryDateLocal: dateLocal,
  fiscalYear: 2627,
  sourceType: 'sale',
  totalDebit: const Money.rupees(1600),
  totalCredit: const Money.rupees(1600),
  lines:
      lines ??
      const [
        JournalLinePosting(
          lineNo: 1,
          accountSystemKey: '#cash',
          debit: Money.rupees(1000),
          credit: Money.zero,
        ),
        JournalLinePosting(
          lineNo: 2,
          accountSystemKey: 'cogs',
          debit: Money.rupees(600),
          credit: Money.zero,
        ),
        JournalLinePosting(
          lineNo: 3,
          accountSystemKey: 'sales',
          debit: Money.zero,
          credit: Money.rupees(1000),
        ),
        JournalLinePosting(
          lineNo: 4,
          accountSystemKey: 'inventory',
          debit: Money.zero,
          credit: Money.rupees(600),
        ),
      ],
);

/// The same sale, on udhaar.
JournalEntryPosting _udhaarEntry() => JournalEntryPosting(
  entryNo: 'JV-2627-00002',
  entryDateUtcMillis: 0,
  entryDateLocal: '2026-08-23',
  fiscalYear: 2627,
  sourceType: 'sale',
  totalDebit: const Money.rupees(1000),
  totalCredit: const Money.rupees(1000),
  lines: const [
    JournalLinePosting(
      lineNo: 1,
      accountSystemKey: 'accounts_receivable',
      debit: Money.rupees(1000),
      credit: Money.zero,
      partyId: 'party-1',
    ),
    JournalLinePosting(
      lineNo: 2,
      accountSystemKey: 'sales',
      debit: Money.zero,
      credit: Money.rupees(1000),
    ),
  ],
);

/// Two units leaving the shelf at Rs 300 each.
StockMovementPosting _movement() => StockMovementPosting(
  itemId: 'item-1',
  txnType: 'sale',
  qtyDelta: const Qty.raw(-2000),
  rate: const Rate.rupees(300),
  valueDelta: const Money.rupees(-600),
  occurredAtUtcMillis: 0,
  occurredOnLocal: '2026-08-23',
  lineNo: 1,
);
