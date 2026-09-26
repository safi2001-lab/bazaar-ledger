import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// Goods going back to the supplier, as rows, before any are written.
///
/// The delivery in every case: ten sacks of rice billed at Rs 120, with Rs 200
/// of freight on top, so the goods are Rs 1,200 and they landed at Rs 1,400.
void main() {
  const builder = PurchaseReturnBuilder();

  const line = BoughtLine(
    documentLineId: 'line-1',
    itemId: 'rice',
    itemName: 'Chawal',
    unitId: 'pcs',
    unitCode: 'pcs',
    boughtQty: Qty.raw(10000),
    alreadyReturned: Qty.zero,
    goodsValue: Money.rupees(1200),
    landedCost: Money.rupees(1400),
  );

  /// Ten already on the shelf at Rs 100 before this delivery, so twenty now
  /// at an average of Rs 120.
  final shelf = {
    'rice': CostPosition.onShelf(
      qty: Qty.units(20),
      avg: const Rate.rupees(120),
    ),
  };

  PurchaseReturnPosting build({
    int qty = 4,
    Money refundNow = Money.zero,
    Money outstanding = const Money.rupees(1400),
    Map<String, CostPosition>? positions,
    BoughtLine bought = line,
    String reason = 'Bori phati hui thi',
  }) => builder.build(
    actor: ActorContext(
      firmId: 'firm-1',
      userId: 'user-1',
      deviceId: 'device-1',
      startedAtUtc: DateTime.utc(2026, 9, 26, 9, 15),
    ),
    draft: PurchaseReturnDraft(
      originalDocumentId: 'pur-1',
      lines: [ReturnLineDraft(documentLineId: 'line-1', qty: Qty.units(qty))],
      reason: reason,
      refundNow: refundNow,
      paymentAccountId: refundNow.isPositive ? 'acct-cash' : null,
    ),
    boughtLines: [bought],
    originalDocNo: 'PUR-2627-0001',
    partyId: 'mill-1',
    originalOutstanding: outstanding,
    positions: positions ?? shelf,
    returnNumber: AllocatedNumber(
      formatted: 'PRN-2627-0001',
      series: 'PRN',
      sequence: 1,
    ),
    journalNumber: AllocatedNumber(
      formatted: 'JV-2627-00001',
      series: 'JV',
      sequence: 1,
    ),
    refundLedgerAccountId: refundNow.isPositive ? 'ledger-cash' : null,
  );

  Money lineOf(PurchaseReturnPosting p, String key, {bool debit = true}) =>
      Money.sum([
        for (final l in p.journal.lines)
          if (l.accountSystemKey == key) debit ? l.debit : l.credit,
      ]);

  group('what goes back, and at what', () {
    test('the supplier credits the goods value, not the freight', () {
      final posting = build();

      expect(posting.document.total, const Money.rupees(480));
      expect(posting.againstBill, const Money.rupees(480));
      expect(lineOf(posting, 'accounts_payable'), const Money.rupees(480));
    });

    test('the shelf gives up what the goods landed at', () {
      // Four tenths of Rs 1,400. Today's average of Rs 120 would give up
      // Rs 480 and leave the delivery's freight blended into what stays.
      final posting = build();

      expect(
        lineOf(posting, 'inventory', debit: false),
        const Money.rupees(560),
      );
      expect(posting.stockMovements.single.qtyDelta, Qty.units(-4));
    });

    test(
      'the freight on goods that went back is the shop\'s, in cost of goods',
      () {
        final posting = build();

        expect(lineOf(posting, 'cogs'), const Money.rupees(80));
      },
    );

    test('what stays is re-averaged over what stays', () {
      // Rs 2,400 less Rs 560, over sixteen sacks.
      final posting = build();

      expect(posting.newAverages['rice'], const Rate.rupees(115));
    });

    test('a whole delivery going back puts the average back where it was', () {
      final posting = build(qty: 10);

      expect(
        posting.newAverages['rice'],
        const Rate.rupees(100),
        reason: 'the shelf still carries a delivery the shop no longer has',
      );
    });

    test('an emptied shelf keeps its last average', () {
      // Nothing left to carry a cost; a zero here would make the next sale
      // after the next delivery look free.
      final posting = build(
        qty: 10,
        positions: {
          'rice': CostPosition.onShelf(
            qty: Qty.units(10),
            avg: const Rate.rupees(140),
          ),
        },
      );

      expect(posting.newAverages['rice'], const Rate.rupees(140));
      expect(
        lineOf(posting, 'inventory', debit: false),
        const Money.rupees(1400),
      );
    });
  });

  group('when the delivery is already paid for', () {
    test('the supplier hands the money back now', () {
      final posting = build(
        outstanding: Money.zero,
        refundNow: const Money.rupees(480),
      );

      expect(posting.againstBill, Money.zero);
      expect(lineOf(posting, '#ledger-cash'), const Money.rupees(480));
    });

    test('credit the delivery cannot absorb has to come back in cash', () {
      expect(
        () => build(outstanding: const Money.rupees(100)),
        throwsA(
          isA<ReturnRefused>().having(
            (e) => e.reason,
            'reason',
            contains('380.00'),
          ),
        ),
      );
    });
  });

  group('what a return to the supplier refuses', () {
    test('more than came in on that delivery', () {
      expect(() => build(qty: 11), throwsA(isA<ReturnRefused>()));
    });

    test('more than earlier returns left', () {
      expect(
        () => build(
          qty: 5,
          bought: const BoughtLine(
            documentLineId: 'line-1',
            itemId: 'rice',
            itemName: 'Chawal',
            unitId: 'pcs',
            unitCode: 'pcs',
            boughtQty: Qty.raw(10000),
            alreadyReturned: Qty.raw(6000),
            goodsValue: Money.rupees(1200),
            landedCost: Money.rupees(1400),
          ),
        ),
        throwsA(isA<ReturnRefused>()),
      );
    });

    test('goods that have already been sold', () {
      expect(
        () => build(
          qty: 4,
          positions: {
            'rice': CostPosition.onShelf(
              qty: Qty.units(3),
              avg: const Rate.rupees(120),
            ),
          },
        ),
        throwsA(
          isA<ReturnRefused>().having(
            (e) => e.reason,
            'reason',
            contains('already been sold'),
          ),
        ),
      );
    });

    test('a return that does not say why', () {
      expect(() => build(reason: '  '), throwsA(isA<ReturnRefused>()));
    });

    test('more cash back than the goods were billed at', () {
      expect(
        () => build(refundNow: const Money.rupees(481)),
        throwsA(isA<ReturnRefused>()),
      );
    });
  });

  test('every return balances, whatever the quantity', () {
    for (var qty = 1; qty <= 10; qty++) {
      final posting = build(qty: qty);
      final journal = posting.journal;
      expect(
        Money.sum([for (final l in journal.lines) l.debit]),
        Money.sum([for (final l in journal.lines) l.credit]),
        reason: 'returning $qty',
      );
    }
  });
}
