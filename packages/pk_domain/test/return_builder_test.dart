import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// A customer bringing goods back.
///
/// Distinct from a void, and the distinction is the point. A void says the
/// bill should never have happened; a return says it did, and then some of it
/// came back. A shopkeeper who sold five things and had one returned cannot
/// void the bill — the other four were sold and the customer keeps them.
void main() {
  const builder = ReturnBuilder();

  ReturnPosting build({
    List<ReturnLineDraft>? lines,
    List<SoldLine>? sold,
    String reason = 'Packet phata hua tha',
    Money refundNow = Money.zero,
    String? partyId = 'party-1',
    String? refundAccount = 'ledger-cash',
  }) => builder.build(
    actor: _actor(),
    draft: ReturnDraft(
      originalDocumentId: 'doc-1',
      reason: reason,
      refundNow: refundNow,
      lines:
          lines ??
          const [ReturnLineDraft(documentLineId: 'l1', qty: Qty.raw(1000))],
    ),
    soldLines: sold ?? [_sold()],
    originalDocNo: 'INV-2627-0001',
    partyId: partyId,
    returnNumber: _number('SRN-2627-0001', 'SRN'),
    journalNumber: _number('JV-2627-00007', 'JV'),
    refundLedgerAccountId: refundAccount,
  );

  Money debits(ReturnPosting p) =>
      Money.sum([for (final l in p.journal.lines) l.debit]);
  Money credits(ReturnPosting p) =>
      Money.sum([for (final l in p.journal.lines) l.credit]);

  group('part of a bill can come back', () {
    test('one unit off a line of five', () {
      // The case a void cannot express. Four were sold and stay sold.
      final posting = build(
        sold: [_sold(qty: 5, rateRupees: 150, costRupees: 500)],
        lines: const [
          ReturnLineDraft(documentLineId: 'l1', qty: Qty.raw(1000)),
        ],
      );

      expect(posting.document.total, const Money.rupees(150));
      expect(posting.lines.single.qty, Qty.units(1));
      expect(posting.stockMovements.single.qtyDelta, Qty.units(1));
    });

    test('the whole line at once', () {
      final posting = build(
        sold: [_sold(qty: 2, rateRupees: 150, costRupees: 180)],
        lines: const [
          ReturnLineDraft(documentLineId: 'l1', qty: Qty.raw(2000)),
        ],
      );

      expect(posting.document.total, const Money.rupees(300));
      expect(posting.document.cost, const Money.rupees(180));
    });

    test('several lines in one visit', () {
      final posting = build(
        sold: [
          _sold(qty: 2, rateRupees: 150, costRupees: 180),
          _sold(id: 'l2', qty: 1, rateRupees: 40, costRupees: 25),
        ],
        lines: const [
          ReturnLineDraft(documentLineId: 'l1', qty: Qty.raw(1000)),
          ReturnLineDraft(documentLineId: 'l2', qty: Qty.raw(1000)),
        ],
      );

      expect(posting.lines, hasLength(2));
      expect(posting.document.total, const Money.rupees(190));
    });
  });

  group('the cost the goods come back at', () {
    test('is what they left at, not what stock costs today', () {
      // The single most important decision here. Stock has moved since;
      // bringing a tin back at today's cost would book a profit or a loss on
      // a customer changing their mind, and the difference would land in no
      // account at all.
      final posting = build(
        sold: [_sold(qty: 1, rateRupees: 150, costRupees: 90)],
      );

      expect(posting.document.cost, const Money.rupees(90));
      expect(posting.stockMovements.single.valueDelta, const Money.rupees(90));
      expect(
        posting.journal.lines
            .singleWhere((l) => l.accountSystemKey == 'inventory')
            .debit,
        const Money.rupees(90),
      );
    });

    test('is pro-rated when only some of a line comes back', () {
      // Rs 500 of cost across five units, one returning: Rs 100.
      final posting = build(
        sold: [_sold(qty: 5, rateRupees: 150, costRupees: 500)],
        lines: const [
          ReturnLineDraft(documentLineId: 'l1', qty: Qty.raw(1000)),
        ],
      );

      expect(posting.document.cost, const Money.rupees(100));
    });

    test('and the pro-rating never loses a paisa', () {
      // Rs 100.00 across three units. One coming back cannot be a third of a
      // paisa, and the split has to be a whole number that still adds up.
      final posting = build(
        sold: [_sold(qty: 3, rateRupees: 150, costRupees: 0, costPaisa: 10000)],
        lines: const [
          ReturnLineDraft(documentLineId: 'l1', qty: Qty.raw(1000)),
        ],
      );

      expect(posting.document.cost.inPaisa, anyOf(3333, 3334));
      expect(debits(posting), credits(posting));
    });

    test('a zero-cost line comes back at zero, not at a divide by zero', () {
      // An item created without opening stock has no cost until a delivery
      // lands, and a sale off it snapshots zero.
      final posting = build(
        sold: [_sold(qty: 1, rateRupees: 150, costRupees: 0)],
      );

      expect(posting.document.cost, Money.zero);
      expect(posting.stockMovements.single.rate, const Rate.raw(0));
      expect(debits(posting), credits(posting));
    });
  });

  group('the money', () {
    test('goes back on the khata when nothing is handed over', () {
      final posting = build(sold: [_sold(qty: 1, rateRupees: 150)]);

      final receivable = posting.journal.lines.singleWhere(
        (l) => l.accountSystemKey == 'accounts_receivable',
      );
      expect(receivable.credit, const Money.rupees(150));
      expect(receivable.partyId, 'party-1');
      expect(posting.refund, Money.zero);
    });

    test('comes out of the drawer when it is handed over', () {
      final posting = build(
        sold: [_sold(qty: 1, rateRupees: 150)],
        refundNow: const Money.rupees(150),
      );

      expect(
        posting.journal.lines
            .singleWhere((l) => l.accountSystemKey == '#ledger-cash')
            .credit,
        const Money.rupees(150),
      );
      expect(
        posting.journal.lines.any(
          (l) => l.accountSystemKey == 'accounts_receivable',
        ),
        isFalse,
      );
    });

    test('splits between the two when only some is handed over', () {
      final posting = build(
        sold: [_sold(qty: 1, rateRupees: 150)],
        refundNow: const Money.rupees(50),
      );

      expect(
        posting.journal.lines
            .singleWhere((l) => l.accountSystemKey == '#ledger-cash')
            .credit,
        const Money.rupees(50),
      );
      expect(
        posting.journal.lines
            .singleWhere((l) => l.accountSystemKey == 'accounts_receivable')
            .credit,
        const Money.rupees(100),
      );
    });

    test('is a debit to Sales Returns, never a debit to Sales', () {
      // A contra-revenue account, because a shopkeeper who took Rs 40,000 of
      // returns in a month needs to see that number. Netting it into Sales
      // hides it.
      final posting = build(sold: [_sold(qty: 1, rateRupees: 150)]);

      expect(posting.journal.lines.first.accountSystemKey, 'sales_returns');
      expect(
        posting.journal.lines.any((l) => l.accountSystemKey == 'sales'),
        isFalse,
      );
    });
  });

  group('what it refuses', () {
    test('more than was sold', () {
      expect(
        () => build(
          sold: [_sold(qty: 2)],
          lines: const [
            ReturnLineDraft(documentLineId: 'l1', qty: Qty.raw(3000)),
          ],
        ),
        throwsA(isA<ReturnRefused>()),
      );
    });

    test('more than is LEFT after an earlier return', () {
      // Across visits, not just within one. Without counting what earlier
      // returns took, a shop can be walked out of its entire stock one bill
      // at a time.
      expect(
        () => build(
          sold: [_sold(qty: 2, alreadyReturned: 1)],
          lines: const [
            ReturnLineDraft(documentLineId: 'l1', qty: Qty.raw(2000)),
          ],
        ),
        throwsA(isA<ReturnRefused>()),
      );

      // And exactly what is left is fine.
      expect(
        build(
          sold: [_sold(qty: 2, alreadyReturned: 1)],
          lines: const [
            ReturnLineDraft(documentLineId: 'l1', qty: Qty.raw(1000)),
          ],
        ).lines,
        hasLength(1),
      );
    });

    test('a line that is not on that bill', () {
      expect(
        () => build(
          lines: const [
            ReturnLineDraft(documentLineId: 'somewhere-else', qty: Qty.raw(1)),
          ],
        ),
        throwsA(isA<ReturnRefused>()),
      );
    });

    test('a return of nothing, and a return with no lines', () {
      expect(
        () => build(
          lines: const [ReturnLineDraft(documentLineId: 'l1', qty: Qty.zero)],
        ),
        throwsA(isA<ReturnRefused>()),
      );
      expect(() => build(lines: const []), throwsA(isA<ReturnRefused>()));
    });

    test('a return with no reason', () {
      expect(() => build(reason: '  '), throwsA(isA<ReturnRefused>()));
    });

    test('handing back more than the goods were sold for', () {
      expect(
        () => build(
          sold: [_sold(qty: 1, rateRupees: 150)],
          refundNow: const Money.rupees(500),
        ),
        throwsA(isA<ReturnRefused>()),
      );
    });

    test('a walk-in return that is not paid back in full', () {
      // There is no khata to put the credit on, and an unbalanced entry is a
      // worse way to find that out.
      expect(
        () => build(
          sold: [_sold(qty: 1, rateRupees: 150)],
          partyId: null,
          refundNow: const Money.rupees(50),
        ),
        throwsA(isA<ReturnRefused>()),
      );

      // Paid in full it is fine.
      expect(
        build(
          sold: [_sold(qty: 1, rateRupees: 150)],
          partyId: null,
          refundNow: const Money.rupees(150),
        ).refund,
        const Money.rupees(150),
      );
    });

    test('a refund with no account for it to come out of', () {
      expect(
        () => build(refundNow: const Money.rupees(10), refundAccount: null),
        throwsA(isA<ReturnRefused>()),
      );
    });
  });

  group('the entry balances', () {
    test('across every shape of return', () {
      for (final refund in [0, 1, 74, 150]) {
        final posting = build(
          sold: [_sold(qty: 1, rateRupees: 150, costRupees: 90)],
          refundNow: Money.rupees(refund),
        );
        expect(
          debits(posting),
          credits(posting),
          reason: 'refund of $refund did not balance',
        );
      }
    });

    test('and the return points at the bill it came off', () {
      final posting = build();

      expect(posting.originalDocumentId, 'doc-1');
      expect(posting.journal.narration, contains('INV-2627-0001'));
      expect(posting.auditSummary, contains('INV-2627-0001'));
      expect(posting.auditSummary, contains('Packet phata hua tha'));
      expect(posting.document.docType, 'sale_return');
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

SoldLine _sold({
  String id = 'l1',
  int qty = 1,
  int rateRupees = 150,
  int costRupees = 90,
  int costPaisa = 0,
  int alreadyReturned = 0,
}) => SoldLine(
  documentLineId: id,
  itemId: 'item-$id',
  itemName: 'Chawal Basmati',
  unitId: 'unit-1',
  unitCode: 'pcs',
  soldQty: Qty.units(qty),
  alreadyReturned: Qty.units(alreadyReturned),
  rate: Rate.rupees(rateRupees),
  cost: Money.paisa(costRupees * 100 + costPaisa),
);
