import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// How money coming across the counter turns into rows.
///
/// Every case here is one an adversarial audit found the previous
/// implementation getting wrong, and each one failed the same way: the
/// calculator produced something the schema would refuse three layers later,
/// so the shopkeeper saw a raw SQLite constraint error on a sale they had
/// already been told was going through.
void main() {
  const calculator = SaleCalculator();

  SaleDraft billOf(int rupees, List<TenderDraft> tenders) => SaleDraft(
        lines: [
          SaleLineDraft(
            itemId: 'I1',
            itemName: 'Cooking Oil 5L',
            qty: Qty.one,
            baseQty: Qty.one,
            unitCode: 'pcs',
            rate: Rate.rupees(rupees),
          ),
        ],
        tenders: tenders,
        roundToRupee: false,
      );

  const context = TaxContext(
    isSellerRegistered: false,
    buyerIsRegistered: false,
    buyerIsOnAtl: null,
    province: 'punjab',
    pricesIncludeTax: false,
    ruleVersion: 'test',
  );

  TenderDraft cash(int rupees, {int? tendered}) => TenderDraft(
        paymentAccountId: 'PA-CASH',
        mode: 'cash',
        amount: Money.rupees(rupees),
        tendered: tendered == null ? null : Money.rupees(tendered),
      );

  TenderDraft digital(int rupees, {String mode = 'easypaisa'}) => TenderDraft(
        paymentAccountId: 'PA-$mode',
        mode: mode,
        amount: Money.rupees(rupees),
      );

  group('change', () {
    test('a cash tender capped at what is due gives the rest back', () {
      final sale = calculator.calculate(billOf(100, [cash(150)]), context);

      expect(sale.paid, Money.rupees(100));
      expect(sale.changeDue, Money.rupees(50));
      expect(sale.balance, Money.zero);
      expect(sale.tenders.single.applied, Money.rupees(100));
      expect(sale.tenders.single.change, Money.rupees(50));
    });

    test('`tendered` is the change basis, exactly as its doc promises', () {
      // A cashier who types "the bill is 100, they gave me a 500 note" is
      // saying something different from "apply 500 to this bill", and the
      // field that says so was being ignored: change came out as zero.
      final sale = calculator.calculate(
        billOf(100, [cash(100, tendered: 500)]),
        context,
      );

      expect(sale.paid, Money.rupees(100));
      expect(sale.changeDue, Money.rupees(400));
      expect(sale.tenders.single.offered, Money.rupees(500));
    });

    test('two cash tenders share one bill without inventing change', () {
      final sale =
          calculator.calculate(billOf(100, [cash(60), cash(60)]), context);

      expect(sale.paid, Money.rupees(100));
      expect(sale.changeDue, Money.rupees(20));
      // The second note is the one that overpaid, so the change hangs off it —
      // not off whichever tender happened to be written first.
      expect(sale.tenders, hasLength(2));
      expect(sale.tenders.first.applied, Money.rupees(60));
      expect(sale.tenders.first.change, Money.zero);
      expect(sale.tenders.last.applied, Money.rupees(40));
      expect(sale.tenders.last.change, Money.rupees(20));
    });

    test('every posted tender satisfies offered = applied + change', () {
      for (final tenders in [
        [cash(150)],
        [cash(60), cash(60)],
        [digital(40), cash(100)],
        [cash(100, tendered: 500)],
      ]) {
        final sale = calculator.calculate(billOf(100, tenders), context);
        for (final t in sale.tenders) {
          expect(
            t.offered,
            t.applied + t.change,
            reason: 'a payment row must account for the whole note',
          );
        }
      }
    });
  });

  group('overpayment', () {
    test('a transfer above the bill is refused outright', () {
      expect(
        () => calculator.calculate(billOf(100, [digital(150)]), context),
        throwsArgumentError,
      );
    });

    test('cash offered on top of an exact transfer is handed straight back',
        () {
      // The old code wrote this as a payment row with `amount_paisa = 0` and
      // change of 50, which the schema's `CHECK (amount_paisa > 0)` refused —
      // three layers below the shopkeeper, as a raw constraint error.
      final sale = calculator.calculate(
        billOf(100, [digital(100), cash(50)]),
        context,
      );

      expect(sale.tenders, hasLength(1));
      expect(sale.tenders.single.draft.mode, 'easypaisa');
      expect(sale.paid, Money.rupees(100));
      expect(
        sale.changeDue,
        Money.zero,
        reason: 'nothing entered the drawer, so nothing left it',
      );
    });

    test('a card overpayment cannot post a negative receivable', () {
      // This one balanced — debits and credits still summed equal — and then
      // failed on `CHECK (debit_paisa >= 0)`.
      expect(
        () => calculator.calculate(
          billOf(100, [digital(150, mode: 'card'), cash(10)]),
          context,
        ),
        throwsArgumentError,
      );
    });

    test('exact digital settlement is fine', () {
      final sale = calculator.calculate(billOf(100, [digital(100)]), context);
      expect(sale.paid, Money.rupees(100));
      expect(sale.changeDue, Money.zero);
      expect(sale.balance, Money.zero);
    });
  });

  group('rows that would not be written', () {
    test('a tender that settles nothing is not a payment', () {
      final sale =
          calculator.calculate(billOf(100, [cash(100), cash(50)]), context);

      // The first note settles the bill; the second is handed straight back
      // and is not a payment at all. Writing it anyway used to draw a receipt
      // number and then skip the row, leaving a permanent gap in the series
      // on the SUCCESS path — the one place a rollback test never looks.
      expect(sale.tenders, hasLength(1));
      expect(sale.tenders.single.applied, Money.rupees(100));
      expect(sale.changeDue, Money.zero);

      final withNothing = calculator.calculate(
        billOf(100, [cash(100), cash(0)]),
        context,
      );
      expect(withNothing.tenders, hasLength(1));
    });
  });

  group('s.21(s) cash threshold', () {
    // Finance Act 2025: 50% of an expenditure is disallowed where a single
    // invoice above Rs 200,000 is settled otherwise than through a banking or
    // digital channel.
    test('above the threshold in cash is flagged', () {
      final sale =
          calculator.calculate(billOf(200001, [cash(200001)]), context);
      expect(sale.cashThresholdBreached, isTrue);
    });

    test('exactly Rs 200,000 is not flagged — the statute says above', () {
      final sale =
          calculator.calculate(billOf(200000, [cash(200000)]), context);
      expect(sale.cashThresholdBreached, isFalse);
    });

    test('above the threshold through a digital channel is not flagged', () {
      final sale = calculator.calculate(
        billOf(200001, [digital(200001, mode: 'raast')]),
        context,
      );
      expect(sale.cashThresholdBreached, isFalse);
    });

    test('an adjustment is not cash, and is not a banking channel either', () {
      // The old test asked whether any cash was applied. An adjustment is
      // neither, and is squarely inside what the section covers.
      final sale = calculator.calculate(
        billOf(250000, [
          const TenderDraft(
            paymentAccountId: 'PA-ADJ',
            mode: 'adjustment',
            amount: Money.paisa(25000000),
          ),
        ]),
        context,
      );
      expect(sale.cashThresholdBreached, isTrue);
    });

    test('a part-cash settlement above the threshold is flagged', () {
      final sale = calculator.calculate(
        billOf(250000, [digital(240000), cash(10000)]),
        context,
      );
      expect(sale.cashThresholdBreached, isTrue);
    });
  });
}
