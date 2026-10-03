import 'dart:math';

import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// A service given back (M61): the province's tax on it comes back to the
/// province, row by row at the rate each part was charged, under the
/// province's own code — never as federal sales tax — and to the paisa.
void main() {
  const builder = ReturnBuilder();
  final pra = ServiceTaxSetting.publishedFor(ServiceTaxAuthority.pra)!;

  ReturnPosting build(SoldLine sold, Qty qty, {Money? refund}) => builder.build(
    actor: ActorContext(
      firmId: 'firm-1',
      userId: 'user-1',
      deviceId: 'device-1',
      startedAtUtc: DateTime.utc(2026, 10, 3, 9),
    ),
    draft: ReturnDraft(
      originalDocumentId: 'doc-1',
      reason: 'Customer not happy',
      refundNow: refund ?? Money.zero,
      paymentAccountId: refund == null ? null : 'cash',
      lines: [ReturnLineDraft(documentLineId: sold.documentLineId, qty: qty)],
    ),
    soldLines: [sold],
    originalDocNo: 'INV-2627-0009',
    partyId: 'party-1',
    originalOutstanding: Money.zero,
    returnNumber: const AllocatedNumber(
      formatted: 'SRN-2627-0001',
      series: 'SRN',
      sequence: 1,
    ),
    journalNumber: const AllocatedNumber(
      formatted: 'JV-2627-0001',
      series: 'JV',
      sequence: 1,
    ),
    refundLedgerAccountId: refund == null ? null : 'ledger-cash',
  );

  /// A service line of [units] at [rupees] each, taxed by PRA with [share]
  /// of it paid by card, exactly as the counter charges it (M59).
  SoldLine service({
    int units = 1,
    int rupees = 1000,
    DigitalShare share = DigitalShare.none,
    bool inclusive = false,
    int alreadyReturned = 0,
  }) {
    final value = Money.rupees(rupees * units);
    final charges = serviceTaxCharges(
      value: value,
      setting: pra,
      share: share,
      inclusive: inclusive,
    );
    final tax = Money.sum([for (final c in charges) c.amount]);
    return SoldLine(
      documentLineId: 'l1',
      itemId: 'item-cut',
      itemName: 'Bridal makeup',
      unitId: 'unit-1',
      unitCode: 'pcs',
      soldQty: Qty.units(units),
      alreadyReturned: Qty.raw(alreadyReturned),
      rate: Rate.rupees(rupees),
      cost: Money.zero,
      charged: inclusive ? value : value + tax,
      provincialTaxes: [
        for (final c in charges)
          SoldTax(
            code: c.code,
            rateBp: c.rateBp,
            base: c.base,
            amount: c.amount,
            isInclusive: c.isInclusive,
          ),
      ]..sort((a, b) => a.code.compareTo(b.code)),
      taxInclusive: inclusive,
    );
  }

  group('a service given back', () {
    test(
      'paid part by card, it comes back as two rows of the province\'s own, each at the rate it was charged, and never as federal tax',
      () {
        // M59's bridal makeup: Rs 500 by card and the rest in cash, so
        // 46296 paisa at 8% and 53704 at 16%.
        final sold = service(share: const DigitalShare(50000, 108000));
        expect(sold.provincialTaxes, const [
          SoldTax(
            code: 'PRA_CARD',
            rateBp: 800,
            base: Money.paisa(46296),
            amount: Money.paisa(3704),
          ),
          SoldTax(
            code: 'PRA_STD',
            rateBp: 1600,
            base: Money.paisa(53704),
            amount: Money.paisa(8593),
          ),
        ]);

        final back = build(sold, Qty.one);
        final taxes = back.lines.single.taxes;
        expect(
          [for (final t in taxes) (t.kind, t.code, t.rateBp)],
          [
            (TaxKind.provincialSt, 'PRA_CARD_RETURN', 800),
            (TaxKind.provincialSt, 'PRA_STD_RETURN', 1600),
          ],
        );
        expect(
          [for (final t in taxes) t.amount],
          const [Money.paisa(3704), Money.paisa(8593)],
        );
        expect(
          [for (final t in taxes) t.base],
          const [Money.paisa(46296), Money.paisa(53704)],
        );
        expect(taxes.where((t) => t.kind == TaxKind.salesTax), isEmpty);
        expect(back.document.total, const Money.paisa(112297));
        expect(back.document.taxable, const Money.rupees(1000));
        expect(back.document.tax, const Money.paisa(12297));
        // Off Output Sales Tax, where the sale put it, and balanced.
        final outputTax = back.journal.lines.singleWhere(
          (l) => l.accountSystemKey == 'output_tax',
        );
        expect(outputTax.debit, const Money.paisa(12297));
        back.assertBalanced();
      },
    );

    test(
      'given back a piece at a time, every row of the province\'s tax comes back to the paisa it was charged, never more',
      () {
        final random = Random(61);
        for (var round = 0; round < 300; round++) {
          final units = 1 + random.nextInt(12);
          final rupees = 1 + random.nextInt(4000);
          final whole = rupees * units * 108;
          final card = random.nextInt(whole + 1);
          final inclusive = random.nextBool();
          var sold = service(
            units: units,
            rupees: rupees,
            inclusive: inclusive,
            share: card == 0
                ? DigitalShare.none
                : card >= whole
                ? DigitalShare.all
                : DigitalShare(card, whole),
          );
          final owed = {for (final t in sold.provincialTaxes) t.code: t.amount};
          final given = <String, Money>{};
          var refunded = Money.zero;
          while (sold.returnable.isPositive) {
            final left = sold.returnable.inThousandths ~/ 1000;
            final take = Qty.units(1 + random.nextInt(left));
            final back = build(sold, take);
            back.assertBalanced();
            final line = back.lines.single;
            expect(
              line.lineTotal,
              line.taxable + Money.sum([for (final t in line.taxes) t.amount]),
              reason: 'round $round: the refund is the value and its taxes',
            );
            for (final t in line.taxes) {
              expect(t.kind, TaxKind.provincialSt);
              final charged = serviceTaxChargedCode(t.code);
              given[charged] = (given[charged] ?? Money.zero) + t.amount;
              expect(
                given[charged]! <= owed[charged]!,
                isTrue,
                reason: 'round $round: never more than $charged carried',
              );
            }
            refunded += back.document.total;
            sold = SoldLine(
              documentLineId: sold.documentLineId,
              itemId: sold.itemId,
              itemName: sold.itemName,
              unitId: sold.unitId,
              unitCode: sold.unitCode,
              soldQty: sold.soldQty,
              alreadyReturned: Qty.raw(
                sold.alreadyReturned.inThousandths + take.inThousandths,
              ),
              rate: sold.rate,
              cost: sold.cost,
              charged: sold.charged,
              provincialTaxes: sold.provincialTaxes,
              taxInclusive: sold.taxInclusive,
            );
          }
          expect(given, owed, reason: 'round $round: all of it, exactly');
          expect(refunded, sold.charged, reason: 'round $round');
        }
      },
    );

    test(
      'a tax given back reads as the tax it was charged, owed to its own authority',
      () {
        expect(serviceTaxReturnCode('PRA_CARD'), 'PRA_CARD_RETURN');
        expect(serviceTaxReturnCode('PRA_CARD_RETURN'), 'PRA_CARD_RETURN');
        expect(serviceTaxChargedCode('SRB_STD_RETURN'), 'SRB_STD');
        expect(serviceTaxChargedCode('SRB_STD'), 'SRB_STD');
        expect(isServiceTaxReturnCode('KPRA_STD_RETURN'), isTrue);
        expect(isServiceTaxReturnCode('KPRA_STD'), isFalse);
        expect(serviceTaxLabel('PRA_CARD_RETURN', 800), 'PRA 8% (card)');
        expect(serviceTaxLabel('PRA_STD_RETURN', 1600), 'PRA 16%');
        expect(serviceTaxAuthorityOf('PRA_CARD'), 'PRA');
        expect(serviceTaxAuthorityOf('KPRA_STD_RETURN'), 'KPRA');
        expect(serviceTaxAuthorityOf('BRA_CARD'), 'BRA');
      },
    );

    test(
      'goods given back still come back as federal tax, and a service with no provincial tax gives none back',
      () {
        const goods = SoldLine(
          documentLineId: 'l1',
          itemId: 'item-oil',
          itemName: 'Cooking oil',
          unitId: 'unit-1',
          unitCode: 'pcs',
          soldQty: Qty.raw(1000),
          alreadyReturned: Qty.zero,
          rate: Rate.rupees(1000),
          cost: Money.rupees(800),
          salesTax: Money.rupees(180),
          salesTaxBp: 1800,
        );
        final back = build(goods, Qty.one);
        expect(
          [for (final t in back.lines.single.taxes) t.code],
          ['ST_RETURN'],
        );
        expect(back.document.tax, const Money.rupees(180));

        final untaxed = SoldLine(
          documentLineId: 'l1',
          itemId: 'item-cut',
          itemName: 'Haircut',
          unitId: 'unit-1',
          unitCode: 'pcs',
          soldQty: Qty.units(1),
          alreadyReturned: Qty.zero,
          rate: Rate.rupees(500),
          cost: Money.zero,
        );
        final none = build(untaxed, Qty.one);
        expect(none.lines.single.taxes, isEmpty);
        expect(none.document.total, const Money.rupees(500));
      },
    );
  });

  group('the tax invoice of a split service', () {
    test(
      'a line taxed at two rates says both, and how the line was split, never the higher rate alone',
      () {
        const split = ReceiptLineTax(
          valueExclTax: Money.rupees(1000),
          salesTax: Money.paisa(12297),
          rateBp: 1600,
          rateParts: [
            ReceiptRatePart(
              code: 'PRA_STD',
              rateBp: 1600,
              base: Money.paisa(53704),
            ),
            ReceiptRatePart(
              code: 'PRA_CARD',
              rateBp: 800,
              base: Money.paisa(46296),
            ),
          ],
        );
        expect(split.rateLabel, '16% / 8%');
        expect(split.rateSplit, 'PRA 16% on Rs 537.04, 8% (card) on Rs 462.96');

        const one = ReceiptLineTax(
          valueExclTax: Money.rupees(1000),
          salesTax: Money.rupees(80),
          rateBp: 800,
          rateParts: [
            ReceiptRatePart(
              code: 'PRA_CARD',
              rateBp: 800,
              base: Money.rupees(1000),
            ),
          ],
        );
        expect(one.rateLabel, '8%');
        expect(one.rateSplit, isNull);
      },
    );
  });
}
