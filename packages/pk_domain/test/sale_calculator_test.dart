import 'dart:math';

import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

void main() {
  const calculator = SaleCalculator();
  const untaxed = TaxContext(
    isSellerRegistered: false,
    buyerIsRegistered: false,
    buyerIsOnAtl: null,
    province: 'punjab',
    pricesIncludeTax: false,
    ruleVersion: 'untaxed-v1',
  );

  SaleLineDraft line({
    required String name,
    required String qty,
    required Rate rate,
    String unit = 'pcs',
    int discountBp = 0,
    Money? explicitDiscount,
    Rate cost = Rate.zero,
    bool free = false,
  }) {
    final quantity = Qty.parse(qty);
    return SaleLineDraft(
      itemId: 'I-$name',
      itemName: name,
      qty: quantity,
      baseQty: quantity,
      unitCode: unit,
      rate: rate,
      discountBp: discountBp,
      explicitDiscount: explicitDiscount,
      unitCost: cost,
      isFreeItem: free,
    );
  }

  group('the M0 reference sale', () {
    // The acceptance script: two pieces at Rs 2,500 and 3.5 kg at Rs 150,
    // paid in cash. Total Rs 5,525.00 — 552500 paisa, asserted against the
    // app's own database file at the end of the demo run.
    late CalculatedSale sale;

    setUp(() {
      sale = calculator.calculate(
        SaleDraft(
          lines: [
            line(name: 'Cooking Oil 5L', qty: '2', rate: Rate.rupees(2500)),
            line(
              name: 'Mutton',
              qty: '3.5',
              unit: 'kg',
              rate: Rate.rupees(150),
            ),
          ],
          tenders: [
            TenderDraft(
              paymentAccountId: 'PA-CASH',
              mode: 'cash',
              amount: Money.rupees(6000),
              tendered: Money.rupees(6000),
            ),
          ],
        ),
        untaxed,
      );
    });

    test('totals Rs 5,525.00 to the paisa', () {
      expect(sale.subtotal, Money.rupees(5525));
      expect(sale.total, Money.rupees(5525));
      expect(sale.total.inPaisa, 552500);
      expect(sale.tax, Money.zero);
      expect(sale.roundOff, Money.zero);
    });

    test('gives Rs 475.00 change and records the bill as paid', () {
      expect(sale.paid, Money.rupees(5525));
      expect(sale.changeDue, Money.rupees(475));
      expect(sale.balance, Money.zero);
      expect(sale.isFullyPaid, isTrue);
    });

    test('prices the fractional weight line correctly', () {
      // The previous build rendered `quantity.toInt()` in the cart, so 0.750
      // kg of mutton showed as "0" while the arithmetic underneath was right.
      // Here the arithmetic and the display come from the same integer.
      final mutton = sale.lines[1];
      expect(mutton.gross, Money.rupees(525));
      expect(mutton.draft.qty.display, '3.5');
      expect(mutton.lineTotal, Money.rupees(525));
    });

    test('every line total sums back to the bill total', () {
      expect(
        Money.sum([for (final l in sale.lines) l.lineTotal]),
        sale.total,
      );
    });
  });

  group('discounts', () {
    test('a percentage discount is exact in basis points', () {
      final sale = calculator.calculate(
        SaleDraft(
          lines: [
            line(
              name: 'Rice 5kg',
              qty: '1',
              rate: Rate.rupees(1650),
              discountBp: 750, // 7.5%
            ),
          ],
          roundToRupee: false,
        ),
        untaxed,
      );
      // 7.5% of Rs 1,650 is Rs 123.75 exactly. An integer percent could not
      // express the rate and a float could not express the result.
      expect(sale.lines.single.lineDiscount, Money.rupees(123, 75));
      expect(sale.total, Money.rupees(1526, 25));
    });

    test('an amount typed by hand beats the percentage', () {
      // A shopkeeper who says "make it 500" means 500, not 500 rounded through
      // a percentage and back.
      final sale = calculator.calculate(
        SaleDraft(
          lines: [
            line(
              name: 'Rice 5kg',
              qty: '1',
              rate: Rate.rupees(1650),
              discountBp: 750,
              explicitDiscount: Money.rupees(500),
            ),
          ],
        ),
        untaxed,
      );
      expect(sale.lines.single.lineDiscount, Money.rupees(500));
      expect(sale.total, Money.rupees(1150));
    });

    test('a line for no quantity at all is refused here, not by SQLite', () {
      // A zero-quantity line prices to nothing and passes every other guard.
      // Left to reach the database it dies on `CHECK (qty_thousandths <> 0)`
      // — after the documents row has already been inserted. The transaction
      // rolls back so nothing is corrupted, but the cashier is handed an
      // untranslated SQLite string on a sale they were told was going
      // through. This layer's whole job is to catch that here, where the
      // message can name the item and say what to do about it.
      expect(
        () => calculator.calculate(
          SaleDraft(
            lines: [line(name: 'Rice', qty: '0', rate: Rate.rupees(100))],
          ),
          untaxed,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            allOf(contains('Rice'), contains('Remove the line')),
          ),
        ),
      );
    });

    test('a discount larger than the line is refused', () {
      expect(
        () => calculator.calculate(
          SaleDraft(
            lines: [
              line(
                name: 'Rice',
                qty: '1',
                rate: Rate.rupees(100),
                explicitDiscount: Money.rupees(150),
              ),
            ],
          ),
          untaxed,
        ),
        throwsArgumentError,
      );
    });

    test('a bill discount splits across lines and loses nothing', () {
      // Three lines and a discount that does not divide evenly. The parts must
      // re-sum to exactly what was typed, or the invoice total disagrees with
      // the sum of its own lines.
      final sale = calculator.calculate(
        SaleDraft(
          lines: [
            line(name: 'A', qty: '1', rate: Rate.rupees(100)),
            line(name: 'B', qty: '1', rate: Rate.rupees(100)),
            line(name: 'C', qty: '1', rate: Rate.rupees(100)),
          ],
          billDiscount: Money.rupees(10),
          roundToRupee: false,
        ),
        untaxed,
      );

      final parts = [for (final l in sale.lines) l.apportionedBillDiscount];
      expect(Money.sum(parts), Money.rupees(10));
      expect(parts.map((p) => p.inPaisa), [334, 333, 333]);
      expect(sale.total, Money.rupees(290));
      expect(Money.sum([for (final l in sale.lines) l.lineTotal]), sale.total);
    });

    test('a bill discount is pro-rata, not equal', () {
      final sale = calculator.calculate(
        SaleDraft(
          lines: [
            line(name: 'Cheap', qty: '1', rate: Rate.rupees(100)),
            line(name: 'Dear', qty: '1', rate: Rate.rupees(900)),
          ],
          billDiscount: Money.rupees(100),
          roundToRupee: false,
        ),
        untaxed,
      );
      expect(sale.lines[0].apportionedBillDiscount, Money.rupees(10));
      expect(sale.lines[1].apportionedBillDiscount, Money.rupees(90));
    });

    test('a bill discount larger than the bill is refused', () {
      expect(
        () => calculator.calculate(
          SaleDraft(
            lines: [line(name: 'A', qty: '1', rate: Rate.rupees(100))],
            billDiscount: Money.rupees(200),
          ),
          untaxed,
        ),
        throwsArgumentError,
      );
    });
  });

  group('rounding', () {
    test('rounds to the rupee and posts the adjustment', () {
      // Rs 132 per 10 kg of loose atta, 700 g of it: Rs 9.24. Rounded to
      // Rs 9.00, and the 24 paisa goes to the round-off account rather than
      // vanishing into the total.
      final perGram = Rate.fromPack(Money.rupees(132), Qty.units(10000));
      final sale = calculator.calculate(
        SaleDraft(
          lines: [
            SaleLineDraft(
              itemId: 'I-ATTA',
              itemName: 'Atta (loose)',
              qty: Qty.units(700),
              baseQty: Qty.units(700),
              unitCode: 'g',
              rate: perGram,
            ),
          ],
        ),
        untaxed,
      );
      expect(sale.subtotal, Money.rupees(9, 24));
      expect(sale.roundOff, Money.paisa(-24));
      expect(sale.total, Money.rupees(9));
    });

    test('leaves the paisa alone when rounding is off', () {
      final perGram = Rate.fromPack(Money.rupees(132), Qty.units(10000));
      final sale = calculator.calculate(
        SaleDraft(
          lines: [
            SaleLineDraft(
              itemId: 'I-ATTA',
              itemName: 'Atta (loose)',
              qty: Qty.units(700),
              baseQty: Qty.units(700),
              unitCode: 'g',
              rate: perGram,
            ),
          ],
          roundToRupee: false,
        ),
        untaxed,
      );
      expect(sale.total, Money.rupees(9, 24));
      expect(sale.roundOff, Money.zero);
    });
  });

  group('tenders', () {
    test('split tender across bank and cash leaves nothing owing', () {
      final sale = calculator.calculate(
        SaleDraft(
          lines: [line(name: 'A', qty: '1', rate: Rate.rupees(5000))],
          tenders: const [
            TenderDraft(
              paymentAccountId: 'PA-BANK',
              mode: 'easypaisa',
              amount: Money.rupees(3000),
              reference: 'TID 88213',
            ),
            TenderDraft(
              paymentAccountId: 'PA-CASH',
              mode: 'cash',
              amount: Money.rupees(2000),
            ),
          ],
        ),
        untaxed,
      );
      expect(sale.paid, Money.rupees(5000));
      expect(sale.balance, Money.zero);
      expect(sale.changeDue, Money.zero);
    });

    test('a part payment leaves the rest on udhaar', () {
      final sale = calculator.calculate(
        SaleDraft(
          lines: [line(name: 'A', qty: '1', rate: Rate.rupees(5000))],
          partyId: 'P-BILAL',
          tenders: const [
            TenderDraft(
              paymentAccountId: 'PA-CASH',
              mode: 'cash',
              amount: Money.rupees(2000),
            ),
          ],
        ),
        untaxed,
      );
      expect(sale.paid, Money.rupees(2000));
      expect(sale.balance, Money.rupees(3000));
      expect(sale.isFullyPaid, isFalse);
    });

    test('an unpaid bill is entirely udhaar', () {
      final sale = calculator.calculate(
        SaleDraft(
          lines: [line(name: 'A', qty: '1', rate: Rate.rupees(5000))],
          partyId: 'P-BILAL',
        ),
        untaxed,
      );
      expect(sale.paid, Money.zero);
      expect(sale.balance, Money.rupees(5000));
    });

    test('change comes out of the cash tender, never out of a transfer', () {
      final sale = calculator.calculate(
        SaleDraft(
          lines: [line(name: 'A', qty: '1', rate: Rate.rupees(5000))],
          tenders: const [
            TenderDraft(
              paymentAccountId: 'PA-BANK',
              mode: 'raast',
              amount: Money.rupees(4000),
            ),
            TenderDraft(
              paymentAccountId: 'PA-CASH',
              mode: 'cash',
              amount: Money.rupees(2000),
            ),
          ],
        ),
        untaxed,
      );
      expect(sale.paid, Money.rupees(5000));
      expect(sale.changeDue, Money.rupees(1000));
      expect(sale.balance, Money.zero);
    });

    test('refuses an overpayment that has no cash to give change from', () {
      expect(
        () => calculator.calculate(
          SaleDraft(
            lines: [line(name: 'A', qty: '1', rate: Rate.rupees(1000))],
            tenders: const [
              TenderDraft(
                paymentAccountId: 'PA-BANK',
                mode: 'bank_transfer',
                amount: Money.rupees(5000),
              ),
            ],
          ),
          untaxed,
        ),
        throwsArgumentError,
      );
    });
  });

  group('section 21(s) cash threshold', () {
    // Finance Act 2025: 50% of an expenditure is disallowed where a single
    // invoice above Rs 200,000 is settled otherwise than through a banking or
    // digital channel. Nobody else in this market warns about it.
    test('flags a large bill settled in cash', () {
      final sale = calculator.calculate(
        SaleDraft(
          lines: [line(name: 'Bulk', qty: '1', rate: Rate.rupees(250000))],
          tenders: const [
            TenderDraft(
              paymentAccountId: 'PA-CASH',
              mode: 'cash',
              amount: Money.rupees(250000),
            ),
          ],
        ),
        untaxed,
      );
      expect(sale.cashThresholdBreached, isTrue);
    });

    test('does not flag the same bill paid through a bank', () {
      final sale = calculator.calculate(
        SaleDraft(
          lines: [line(name: 'Bulk', qty: '1', rate: Rate.rupees(250000))],
          tenders: const [
            TenderDraft(
              paymentAccountId: 'PA-BANK',
              mode: 'bank_transfer',
              amount: Money.rupees(250000),
            ),
          ],
        ),
        untaxed,
      );
      expect(sale.cashThresholdBreached, isFalse);
    });

    test('does not flag a bill under the threshold', () {
      final sale = calculator.calculate(
        SaleDraft(
          lines: [line(name: 'Normal', qty: '1', rate: Rate.rupees(199999))],
          tenders: const [
            TenderDraft(
              paymentAccountId: 'PA-CASH',
              mode: 'cash',
              amount: Money.rupees(199999),
            ),
          ],
        ),
        untaxed,
      );
      expect(sale.cashThresholdBreached, isFalse);
    });
  });

  group('free items and cost', () {
    test('a free item carries no revenue but still costs', () {
      final sale = calculator.calculate(
        SaleDraft(
          lines: [
            line(
              name: 'Soap',
              qty: '10',
              rate: Rate.rupees(120),
              cost: Rate.rupees(90),
            ),
            line(
              name: 'Soap',
              qty: '1',
              rate: Rate.rupees(120),
              cost: Rate.rupees(90),
              free: true,
            ),
          ],
          roundToRupee: false,
        ),
        untaxed,
      );
      expect(sale.total, Money.rupees(1200));
      expect(sale.cost, Money.rupees(990));
      expect(sale.grossProfit, Money.rupees(210));
    });
  });

  group('invariants', () {
    test('a sale with no lines is refused', () {
      expect(
        () => calculator.calculate(const SaleDraft(lines: []), untaxed),
        throwsArgumentError,
      );
    });

    test('property: lines always re-sum to the bill, across 2000 sales', () {
      // The one arithmetic promise the whole product rests on. If a bill ever
      // disagrees with the sum of its own lines, every report built on top is
      // wrong and nobody finds out for months.
      final rng = Random(20260823);
      for (var i = 0; i < 2000; i++) {
        final count = 1 + rng.nextInt(6);
        final lines = [
          for (var j = 0; j < count; j++)
            SaleLineDraft(
              itemId: 'I$j',
              itemName: 'Item $j',
              qty: Qty.raw(1 + rng.nextInt(20000)),
              baseQty: Qty.raw(1 + rng.nextInt(20000)),
              unitCode: 'pcs',
              rate: Rate.raw(rng.nextInt(50000000)),
              discountBp: rng.nextInt(2000),
            ),
        ];
        final subtotalGuess = Money.sum([
          for (final l in lines) l.rate.amountFor(l.qty),
        ]);
        final billDiscount = subtotalGuess.isZero
            ? Money.zero
            : Money.paisa(rng.nextInt(subtotalGuess.inPaisa ~/ 4 + 1));

        final sale = calculator.calculate(
          SaleDraft(
            lines: lines,
            billDiscount: billDiscount,
            roundToRupee: false,
          ),
          untaxed,
        );

        expect(
          Money.sum([for (final l in sale.lines) l.lineTotal]),
          sale.total,
          reason: 'sale $i lines do not re-sum to the total',
        );
        expect(
          Money.sum([for (final l in sale.lines) l.apportionedBillDiscount]),
          billDiscount,
          reason: 'sale $i lost a paisa apportioning the bill discount',
        );
        expect(
          sale.subtotal - sale.lineDiscountTotal - sale.billDiscount,
          sale.taxable,
          reason: 'sale $i totals do not reconcile',
        );
      }
    });
  });
}
