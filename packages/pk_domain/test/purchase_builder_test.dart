import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// A delivery arriving, as rows, before any of them are written.
///
/// The entry has to balance in every case, and the case that broke the first
/// version of this was a delivery landing on a negative balance: the debit
/// assumed Inventory started at zero while the credit knew it did not.
void main() {
  const builder = PurchaseBuilder();

  PurchasePosting build({
    List<PurchaseLineDraft>? lines,
    Map<String, CostPosition>? positions,
    Money freight = Money.zero,
    Money paid = Money.zero,
    String? ledgerAccountId = 'ledger-cash',
  }) => builder.build(
    actor: _actor(),
    draft: PurchaseDraft(
      partyId: 'supplier-1',
      supplierBillNo: 'SUP/9912',
      freight: freight,
      paid: paid,
      lines: lines ?? [_line('rice', qty: 10, rateRupees: 120)],
    ),
    positions: positions ?? const {},
    billNumber: _number('PUR-2627-0001'),
    journalNumber: _number('JV-2627-00001'),
    ledgerAccountId: ledgerAccountId,
  );

  Money debits(PurchasePosting p) =>
      Money.sum([for (final l in p.journal.lines) l.debit]);
  Money credits(PurchasePosting p) =>
      Money.sum([for (final l in p.journal.lines) l.credit]);

  group('what a delivery does to the cost', () {
    test('the first delivery sets the average', () {
      final posting = build();

      expect(posting.lines.single.avgAfter, const Rate.rupees(120));
      expect(posting.lines.single.balanceAfter, Qty.units(10));
      expect(posting.document.total, const Money.rupees(1200));
    });

    test('a second delivery weights against the shelf', () {
      final posting = build(
        positions: {'rice': _at(qty: 10, avgRupees: 90)},
        lines: [_line('rice', qty: 10, rateRupees: 120)],
      );

      expect(posting.lines.single.avgAfter, const Rate.rupees(105));
      expect(posting.lines.single.balanceAfter, Qty.units(20));
    });

    test('the same item twice on one bill averages against itself', () {
      // A real thing on a wholesale delivery. The second line has to see the
      // shelf as the first line left it, not as it was this morning.
      final posting = build(
        lines: [
          _line('rice', qty: 10, rateRupees: 100),
          _line('rice', qty: 10, rateRupees: 140),
        ],
      );

      expect(posting.lines.first.avgAfter, const Rate.rupees(100));
      expect(posting.lines.last.avgAfter, const Rate.rupees(120));
      expect(posting.lines.last.balanceAfter, Qty.units(20));
    });
  });

  group('freight', () {
    test('is in the cost, apportioned by value', () {
      // Splitting it evenly would put as much delivery cost on a Rs 50 packet
      // as on a Rs 5,000 sack.
      final posting = build(
        lines: [
          _line('rice', qty: 10, rateRupees: 100), // Rs 1,000
          _line('dal', qty: 10, rateRupees: 300), // Rs 3,000
        ],
        freight: const Money.rupees(400),
      );

      expect(posting.lines.first.landedCost, const Money.rupees(1100));
      expect(posting.lines.last.landedCost, const Money.rupees(3300));
      expect(posting.lines.first.avgAfter, const Rate.rupees(110));
      expect(posting.lines.last.avgAfter, const Rate.rupees(330));
    });

    test('never loses a paisa, however awkward the split', () {
      final posting = build(
        lines: [
          _line('a', qty: 1, rateRupees: 1),
          _line('b', qty: 1, rateRupees: 1),
          _line('c', qty: 1, rateRupees: 1),
        ],
        freight: const Money.paisa(100),
      );

      expect(
        Money.sum([for (final l in posting.lines) l.landedCost]),
        const Money.rupees(3) + const Money.paisa(100),
      );
      expect(debits(posting), credits(posting));
    });
  });

  group('the entry balances', () {
    test('on an ordinary credit purchase', () {
      final posting = build();

      expect(debits(posting), credits(posting));
      expect(debits(posting), const Money.rupees(1200));
      expect(
        posting.journal.lines
            .singleWhere((l) => l.accountSystemKey == 'accounts_payable')
            .credit,
        const Money.rupees(1200),
      );
    });

    test('when some was paid at the door', () {
      final posting = build(paid: const Money.rupees(500));

      expect(debits(posting), credits(posting));
      expect(
        posting.journal.lines
            .singleWhere((l) => l.accountSystemKey == '#ledger-cash')
            .credit,
        const Money.rupees(500),
      );
      expect(
        posting.journal.lines
            .singleWhere((l) => l.accountSystemKey == 'accounts_payable')
            .credit,
        const Money.rupees(700),
      );
    });

    test('when the whole bill was paid, with no payable line at all', () {
      final posting = build(paid: const Money.rupees(1200));

      expect(debits(posting), credits(posting));
      expect(
        posting.journal.lines.any(
          (l) => l.accountSystemKey == 'accounts_payable',
        ),
        isFalse,
        reason:
            'a zero payable line claims the supplier is owed nothing '
            'and is owed it by somebody',
      );
    });

    test('when the delivery lands on a negative balance', () {
      // The case that broke the first version. Inventory really held -Rs 300;
      // debiting the landed cost assumed it started at zero and the entry did
      // not balance.
      //
      // The account goes from -300 to +910. The bill is Rs 1,300. The Rs 90
      // difference is what the three missing units really cost beyond what
      // the books took them out at.
      final posting = build(
        positions: {
          'rice': const CostPosition(
            qty: Qty.raw(-3000),
            value: Money.rupees(-300),
            avg: Rate.rupees(100),
          ),
        },
        lines: [_line('rice', qty: 10, rateRupees: 130)],
      );

      expect(debits(posting), credits(posting));

      final inventory = posting.journal.lines.singleWhere(
        (l) => l.accountSystemKey == 'inventory',
      );
      expect(inventory.debit, const Money.rupees(1210));

      final wastage = posting.journal.lines.singleWhere(
        (l) => l.accountSystemKey == 'stock_wastage',
      );
      expect(wastage.debit, const Money.rupees(90));
      expect(posting.shortfall, const Money.rupees(90));
    });

    test('when a paisa cannot land in either place', () {
      final posting = build(
        positions: {
          'rice': CostPosition(
            qty: const Qty.raw(1833),
            value: const Rate.rupees(85).amountFor(const Qty.raw(1833)),
            avg: const Rate.rupees(85),
          ),
        },
        lines: [_line('rice', qty: 1, rateRupees: 100, baseQty: 1500)],
      );

      expect(debits(posting), credits(posting));
      expect(posting.rounding, const Money.paisa(1));
      expect(
        posting.journal.lines
            .singleWhere((l) => l.accountSystemKey == 'cogs')
            .debit,
        const Money.paisa(1),
      );
    });
  });

  group('what it refuses', () {
    test('a bill with no lines', () {
      expect(() => build(lines: const []), throwsA(isA<ArgumentError>()));
    });

    test('paying more than the bill is for', () {
      // Money handed over beyond a bill is an advance to the supplier, not
      // part of what this delivery cost.
      expect(
        () => build(paid: const Money.rupees(5000)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('paying with no account for it to come out of', () {
      expect(
        () => build(paid: const Money.rupees(100), ledgerAccountId: null),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('the rest of the rows', () {
    test('stock moves in, in base units', () {
      // Two maunds is eighty kilos, and the stock ledger only speaks kilos.
      final posting = build(
        lines: [_line('rice', qty: 2, rateRupees: 4000, baseQty: 80000)],
      );

      expect(posting.stockMovements.single.txnType, 'purchase');
      expect(posting.stockMovements.single.qtyDelta, Qty.units(80));
      expect(
        posting.stockMovements.single.valueDelta,
        const Money.rupees(8000),
      );
    });

    test('the supplier is named on the payable line', () {
      final line = build().journal.lines.singleWhere(
        (l) => l.accountSystemKey == 'accounts_payable',
      );
      expect(line.partyId, 'supplier-1');
    });

    test('the audit line carries the supplier own bill number', () {
      // Which is what the shopkeeper matches against the paper. The shop's
      // own series is never the supplier's.
      expect(build().auditSummary, contains('SUP/9912'));
      expect(build().auditSummary, contains('PUR-2627-0001'));
    });

    test('the document is a purchase bill dated today', () {
      final posting = build();
      expect(posting.document.docType, 'purchase_bill');
      expect(posting.document.docDateLocal, '2026-08-23');
      expect(posting.document.fiscalYear, 2627);
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

PurchaseLineDraft _line(
  String itemId, {
  required int qty,
  required int rateRupees,
  int? baseQty,
}) => PurchaseLineDraft(
  itemId: itemId,
  itemName: itemId,
  qty: Qty.units(qty),
  baseQty: baseQty == null ? Qty.units(qty) : Qty.raw(baseQty),
  unitId: 'unit-1',
  unitCode: 'pcs',
  rate: Rate.rupees(rateRupees),
);

CostPosition _at({required int qty, required int avgRupees}) => CostPosition(
  qty: Qty.units(qty),
  value: Rate.rupees(avgRupees).amountFor(Qty.units(qty)),
  avg: Rate.rupees(avgRupees),
);
