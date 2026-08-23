import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// What happens to a bill once tax is real.
///
/// M0 ships [UntaxedEngine], which is the correct behaviour for the majority
/// of this market rather than a placeholder: FBR e-invoicing binds
/// sales-tax-registered persons, and most kiryana stores are not registered.
/// But the calculator's tax path is live code either way, and until now every
/// test ran with the engine that returns nothing — so `byKind`, the taxable
/// base, `beforeRounding` and every tax account in the posting builder could
/// all have returned zero and the suite would have stayed green.
///
/// So these run against a real engine at the real Pakistani rates. It is not
/// the M12 rule pack; it is enough to prove the arithmetic beneath it.
void main() {
  const context = TaxContext(
    isSellerRegistered: true,
    buyerIsRegistered: false,
    buyerIsOnAtl: false,
    province: 'punjab',
    pricesIncludeTax: false,
    ruleVersion: 'test-v1',
  );

  SaleDraft billOf(
    List<(int rupees, int qty)> lines, {
    Money extraCharges = Money.zero,
    Money billDiscount = Money.zero,
    bool roundToRupee = false,
  }) =>
      SaleDraft(
        partyId: 'P-BILAL',
        lines: [
          for (var i = 0; i < lines.length; i++)
            SaleLineDraft(
              itemId: 'I$i',
              itemName: 'Item $i',
              qty: Qty.units(lines[i].$2),
              baseQty: Qty.units(lines[i].$2),
              unitCode: 'pcs',
              rate: Rate.rupees(lines[i].$1),
            ),
        ],
        extraCharges: extraCharges,
        billDiscount: billDiscount,
        roundToRupee: roundToRupee,
      );

  group('sales tax at the standard rate', () {
    const calculator = SaleCalculator(taxEngine: _StandardRateEngine());

    test('18% is charged on the taxable value, to the paisa', () {
      final sale = calculator.calculate(billOf([(1000, 1)]), context);

      expect(sale.taxable, Money.rupees(1000));
      expect(
        sale.tax,
        Money.rupees(180),
        reason: '18% of Rs 1,000 under s.3(1) of the Sales Tax Act 1990',
      );
      expect(sale.total, Money.rupees(1180));
    });

    test('the rate is basis points, so an awkward base stays exact', () {
      // Rs 333.33 at 18% is 59.9994, which must land on 60.00 and not on
      // 59.99 or 60.01. Basis-point arithmetic on integers is the whole
      // reason this layer exists.
      final sale = calculator.calculate(
        SaleDraft(
          partyId: 'P-BILAL',
          lines: [
            SaleLineDraft(
              itemId: 'I1',
              itemName: 'Awkward',
              qty: Qty.one,
              baseQty: Qty.one,
              unitCode: 'pcs',
              rate: Rate.parse('333.33'),
            ),
          ],
          roundToRupee: false,
        ),
        context,
      );
      expect(sale.taxable, Money.paisa(33333));
      expect(sale.tax, Money.paisa(6000));
    });

    test('tax is charged after the discount, never before', () {
      // A shopkeeper who gives Rs 100 off a Rs 1,000 bill owes tax on 900.
      // Charging on the gross is over-collection from the customer and an
      // over-payment to FBR that nobody ever gets back.
      final sale = calculator.calculate(
        billOf([(1000, 1)], billDiscount: Money.rupees(100)),
        context,
      );
      expect(sale.taxable, Money.rupees(900));
      expect(sale.tax, Money.rupees(162));
      expect(sale.total, Money.rupees(1062));
    });

    test('extra charges are not silently taxed', () {
      // Delivery is added after tax here, deliberately. Whether a particular
      // charge is part of the taxable supply is an M12 question with a
      // per-charge answer; what must never happen is the arithmetic deciding
      // it by accident.
      final sale = calculator.calculate(
        billOf([(1000, 1)], extraCharges: Money.rupees(50)),
        context,
      );
      expect(sale.taxable, Money.rupees(1000));
      expect(sale.tax, Money.rupees(180));
      expect(sale.total, Money.rupees(1230));
    });

    test('every line carries its own charge, and they sum to the bill', () {
      final sale =
          calculator.calculate(billOf([(1000, 2), (525, 1)]), context);

      expect(sale.lines, hasLength(2));
      for (final line in sale.lines) {
        expect(line.taxes, hasLength(1));
        expect(line.taxes.single.kind, TaxKind.salesTax);
        expect(line.taxes.single.rateBp, 1800);
        expect(line.taxes.single.base, line.taxable);
      }
      expect(
        sale.tax,
        Money.sum([for (final l in sale.lines) l.tax]),
        reason: 'the bill total is the sum of its lines, never a re-derivation',
      );
    });

    test('rounding to the rupee happens after tax, not before', () {
      final sale = calculator.calculate(
        billOf([(333, 1)], roundToRupee: true),
        context,
      );
      // 333.00 + 59.94 = 392.94, rounded to 393.00.
      expect(sale.tax, Money.paisa(5994));
      expect(sale.roundOff, Money.paisa(6));
      expect(sale.total, Money.rupees(393));
    });
  });

  group('further tax under s.3(1A)', () {
    const calculator = SaleCalculator(taxEngine: _FurtherTaxEngine());

    test('4% on top of the standard rate for a buyer off the ATL', () {
      final sale = calculator.calculate(billOf([(1000, 1)]), context);

      expect(sale.tax, Money.rupees(180));
      expect(
        sale.furtherTax,
        Money.rupees(40),
        reason: '4% since the Finance Act 2023, not the 3% the old spec said',
      );
      expect(sale.total, Money.rupees(1220));
    });

    test('nothing extra for a buyer who is on the ATL', () {
      const onAtl = TaxContext(
        isSellerRegistered: true,
        buyerIsRegistered: true,
        buyerIsOnAtl: true,
        province: 'punjab',
        pricesIncludeTax: false,
        ruleVersion: 'test-v1',
      );
      final sale = calculator.calculate(billOf([(1000, 1)]), onAtl);

      expect(sale.tax, Money.rupees(180));
      expect(sale.furtherTax, Money.zero);
      expect(sale.total, Money.rupees(1180));
    });

    test('unknown ATL standing is not the same as being on it', () {
      // Null means nobody has checked. Treating that as "on the list" is the
      // mistake that under-charges, and the shopkeeper pays the difference.
      const unchecked = TaxContext(
        isSellerRegistered: true,
        buyerIsRegistered: false,
        buyerIsOnAtl: null,
        province: 'punjab',
        pricesIncludeTax: false,
        ruleVersion: 'test-v1',
      );
      final sale = calculator.calculate(billOf([(1000, 1)]), unchecked);
      expect(sale.furtherTax, Money.rupees(40));
    });
  });

  group('the posting', () {
    const calculator = SaleCalculator(taxEngine: _FurtherTaxEngine());
    const builder = SalePostingBuilder();

    test('tax is credited to its own account, never folded into sales', () {
      final draft = billOf([(1000, 1)]);
      final calculated = calculator.calculate(draft, context);
      final posting = builder.build(
        actor: ActorContext(
          firmId: 'F1',
          userId: 'U1',
          deviceId: 'D1',
          startedAtUtc: DateTime.utc(2026, 8, 23),
        ),
        draft: draft,
        calculated: calculated,
        invoiceNumber: const AllocatedNumber(
          series: 'INV-2627',
          sequence: 1,
          formatted: 'INV-2627-0001',
        ),
        journalNumber: const AllocatedNumber(
          series: 'JV-2627',
          sequence: 1,
          formatted: 'JV-2627-00001',
        ),
        paymentNumbers: const [],
        ledgerAccountByPaymentAccount: const {},
      );

      final credits = <String, Money>{};
      for (final line in posting.journal.lines) {
        credits[line.accountSystemKey] =
            (credits[line.accountSystemKey] ?? Money.zero) + line.credit;
      }

      expect(credits['sales'], Money.rupees(1000));
      expect(credits['output_tax'], Money.rupees(180));
      expect(credits['further_tax_payable'], Money.rupees(40));
      // The customer owes the whole bill, tax included.
      final receivable = posting.journal.lines
          .firstWhere((l) => l.accountSystemKey == 'accounts_receivable');
      expect(receivable.debit, Money.rupees(1220));
      posting.assertBalanced();
    });

    test('the line taxes are written with their statutory codes', () {
      final calculated = calculator.calculate(billOf([(1000, 1)]), context);
      final charges = calculated.lines.single.taxes;

      expect(charges.map((c) => c.kind),
          [TaxKind.salesTax, TaxKind.furtherTax]);
      expect(charges.map((c) => c.kind.code), ['sales_tax', 'further_tax']);
      expect(charges.map((c) => c.rateBp), [1800, 400]);
      // The rule version travels with the document so a reprint next year
      // still shows this year's rates.
      expect(calculated.ruleVersion, 'test-v1');
    });
  });

  group('the untaxed engine is a decision, not an omission', () {
    test('an unregistered shop charges nothing at all', () {
      const unregistered = TaxContext(
        isSellerRegistered: false,
        buyerIsRegistered: false,
        buyerIsOnAtl: null,
        province: 'punjab',
        pricesIncludeTax: false,
        ruleVersion: 'untaxed-v1',
      );
      final sale = const SaleCalculator()
          .calculate(billOf([(1000, 1)]), unregistered);

      expect(sale.tax, Money.zero);
      expect(sale.furtherTax, Money.zero);
      expect(sale.total, Money.rupees(1000));
      expect(sale.lines.single.taxes, isEmpty);
    });
  });
}

/// 18% sales tax on everything. Not the M12 rule pack — enough to prove the
/// arithmetic the rule pack will sit on.
final class _StandardRateEngine implements TaxEngine {
  const _StandardRateEngine();

  @override
  String get ruleVersion => 'test-v1';

  @override
  List<TaxCharge> chargesFor({
    required Money taxableBase,
    required Money? mrp,
    required String? itemTaxRuleId,
    required bool isThirdSchedule,
    required TaxContext context,
  }) {
    if (!context.isSellerRegistered) return const [];
    // A 3rd Schedule item is taxed on its printed retail price, not on what
    // it was sold for.
    final base = isThirdSchedule && mrp != null ? mrp : taxableBase;
    return [
      TaxCharge(
        kind: TaxKind.salesTax,
        code: 'ST_STD_18',
        rateBp: 1800,
        base: base,
        amount: base.percentBp(1800),
      ),
    ];
  }
}

/// The standard rate plus further tax at 4% when the buyer is off the ATL.
final class _FurtherTaxEngine implements TaxEngine {
  const _FurtherTaxEngine();

  @override
  String get ruleVersion => 'test-v1';

  @override
  List<TaxCharge> chargesFor({
    required Money taxableBase,
    required Money? mrp,
    required String? itemTaxRuleId,
    required bool isThirdSchedule,
    required TaxContext context,
  }) {
    const standard = _StandardRateEngine();
    final charges = [
      ...standard.chargesFor(
        taxableBase: taxableBase,
        mrp: mrp,
        itemTaxRuleId: itemTaxRuleId,
        isThirdSchedule: isThirdSchedule,
        context: context,
      ),
    ];
    if (!context.isSellerRegistered) return charges;

    // s.3(1A): triggered by the buyer being off the Active Taxpayer List, not
    // by their merely lacking an STRN. Unknown is not the same as on it.
    if (context.buyerIsOnAtl ?? false) return charges;

    charges.add(
      TaxCharge(
        kind: TaxKind.furtherTax,
        code: 'FURTHER_4',
        rateBp: 400,
        base: taxableBase,
        amount: taxableBase.percentBp(400),
      ),
    );
    return charges;
  }
}
