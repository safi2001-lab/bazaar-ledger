import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

const _calculator = SaleCalculator(taxEngine: PakistanTaxEngine());

TaxContext _ctx({
  bool registered = true,
  bool inclusive = false,
  bool named = false,
  bool buyerRegistered = false,
  bool? buyerOnAtl,
}) => TaxContext(
  isSellerRegistered: registered,
  buyerIsRegistered: buyerRegistered,
  buyerIsOnAtl: buyerOnAtl,
  province: 'punjab',
  pricesIncludeTax: inclusive,
  ruleVersion: 'pk-2026-27-v1',
  hasNamedBuyer: named,
);

SaleDraft _sale(int rupees, {bool thirdSchedule = false, String? rule}) =>
    SaleDraft(
      roundToRupee: false,
      lines: [
        SaleLineDraft(
          itemId: 'i',
          itemName: 'Ghee 1kg',
          qty: Qty.units(1),
          baseQty: Qty.units(1),
          unitCode: 'pcs',
          rate: Rate.rupees(rupees),
          isThirdSchedule: thirdSchedule,
          taxRuleId: rule,
        ),
      ],
    );

void main() {
  group('pakistan tax', () {
    test('an unregistered shop charges no tax at all', () {
      final c = _calculator.calculate(_sale(1000), _ctx(registered: false));
      expect(c.tax, Money.zero);
      expect(c.total, const Money.rupees(1000));
    });

    test('a registered shop adds 18% to a price without tax', () {
      final c = _calculator.calculate(_sale(1000), _ctx());
      expect(c.taxable, const Money.rupees(1000));
      expect(c.tax, const Money.rupees(180));
      expect(c.total, const Money.rupees(1180));
    });

    test('a price that includes tax has the 18% taken out of it', () {
      final c = _calculator.calculate(_sale(1180), _ctx(inclusive: true));
      expect(c.taxable, const Money.rupees(1000));
      expect(c.tax, const Money.rupees(180));
      expect(c.total, const Money.rupees(1180));
    });

    test('third schedule goods carry the tax inside the retail price', () {
      final c = _calculator.calculate(_sale(118, thirdSchedule: true), _ctx());
      expect(c.tax, const Money.rupees(18));
      expect(c.total, const Money.rupees(118));
      expect(c.lines.single.taxes.single.code, 'ST_3RD_18');
    });

    test('further tax is charged to a named buyer who is not registered', () {
      final c = _calculator.calculate(_sale(1000), _ctx(named: true));
      expect(c.furtherTax, const Money.rupees(40));
      expect(c.total, const Money.rupees(1220));
    });

    test('a registered buyer off the active list still pays further tax', () {
      final c = _calculator.calculate(
        _sale(1000),
        _ctx(named: true, buyerRegistered: true, buyerOnAtl: false),
      );
      expect(c.furtherTax, const Money.rupees(40));
    });

    test(
      'an active registered buyer, a walk-in and third schedule goods pay none',
      () {
        expect(
          _calculator
              .calculate(
                _sale(1000),
                _ctx(named: true, buyerRegistered: true, buyerOnAtl: true),
              )
              .furtherTax,
          Money.zero,
        );
        expect(
          _calculator.calculate(_sale(1000), _ctx()).furtherTax,
          Money.zero,
        );
        expect(
          _calculator
              .calculate(_sale(118, thirdSchedule: true), _ctx(named: true))
              .furtherTax,
          Money.zero,
        );
      },
    );

    test('exempt and zero-rated goods carry no sales tax', () {
      for (final rule in ['exempt', 'zero_rated']) {
        expect(
          _calculator.calculate(_sale(1000, rule: rule), _ctx()).tax,
          Money.zero,
          reason: rule,
        );
      }
    });
  });
}
