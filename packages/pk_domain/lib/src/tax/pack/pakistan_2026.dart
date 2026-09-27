/// The Pakistan tax pack for the 2026-27 year, computed on the phone and
/// never sent anywhere.
///
/// What it charges, and on whom:
///
///  * **Nothing, for a shop that is not registered for sales tax.** Most
///    kiryana stores are not; a non-Tier-1 retailer pays through the
///    electricity bill under s.3(9) STA, and charging a customer tax the
///    shop never pays over would be taking their money.
///  * **Sales tax at 18%** (s.3(1) STA) on a registered shop's taxable
///    supplies: added to the price, or taken out of it when the shop's
///    prices already include it.
///  * **Third Schedule goods** (packaged goods sold on a printed retail
///    price) carry the tax inside the retail price: it is taken out of what
///    the customer pays, never added on top.
///  * **Further tax at 4%** (s.3(1A) STA, as amended by the Finance Act
///    2023) on a supply to a named buyer who is not registered, or is not
///    on the Active Taxpayers List, or whose standing nobody has checked.
///    Not on Third Schedule goods, and not on a walk-in consumer.
///  * **Exempt and zero-rated** items (an item whose tax rule is `exempt`
///    or `zero_rated`) carry none.
///
/// The rates are those in force for 1 July 2026 to 30 June 2027 as this
/// pack was written; a change of rate is a new pack with a new
/// [ruleVersion], so a bill printed under this one reprints the same.
library;

import 'package:pk_money/pk_money.dart';

import '../tax_charge.dart';

/// Standard sales tax, in basis points.
const standardSalesTaxBp = 1800;

/// Further tax under s.3(1A), in basis points.
const furtherTaxBp = 400;

/// Section 73 STA: above this, a registered buyer who pays a supplier other
/// than through a bank cannot claim the input tax on the supply.
const section73CashLimit = Money.rupees(50000);

/// The item tax rules that carry no sales tax.
const untaxedRules = {'exempt', 'zero_rated'};

final class PakistanTaxEngine implements TaxEngine {
  const PakistanTaxEngine();

  @override
  String get ruleVersion => 'pk-2026-27-v1';

  @override
  List<TaxCharge> chargesFor({
    required Money taxableBase,
    required Money? mrp,
    required String? itemTaxRuleId,
    required bool isThirdSchedule,
    required TaxContext context,
  }) {
    if (!context.isSellerRegistered) return const [];
    if (untaxedRules.contains(itemTaxRuleId)) return const [];
    if (taxableBase.isZero) return const [];

    final inclusive = isThirdSchedule || context.pricesIncludeTax;
    final salesTax = inclusive
        ? _inside(taxableBase, standardSalesTaxBp)
        : taxableBase.percentBp(standardSalesTaxBp);
    final valueOfSupply = inclusive ? taxableBase - salesTax : taxableBase;

    final charges = [
      TaxCharge(
        kind: TaxKind.salesTax,
        code: isThirdSchedule ? 'ST_3RD_18' : 'ST_STD_18',
        rateBp: standardSalesTaxBp,
        base: valueOfSupply,
        amount: salesTax,
        isInclusive: inclusive,
        sroScheduleNo: isThirdSchedule ? '3rd' : null,
      ),
    ];

    final buyerOff = !context.buyerIsRegistered || context.buyerIsOnAtl != true;
    if (!isThirdSchedule && context.hasNamedBuyer && buyerOff) {
      charges.add(
        TaxCharge(
          kind: TaxKind.furtherTax,
          code: 'FURTHER_4',
          rateBp: furtherTaxBp,
          base: valueOfSupply,
          amount: valueOfSupply.percentBp(furtherTaxBp),
        ),
      );
    }
    return charges;
  }

  /// The tax inside a price that includes it: price x rate / (1 + rate),
  /// rounded half up to the paisa.
  static Money _inside(Money price, int rateBp) {
    final numerator = price.inPaisa * rateBp;
    final denominator = 10000 + rateBp;
    final q = numerator ~/ denominator;
    final r = numerator.remainder(denominator).abs() * 2;
    return Money.paisa(r >= denominator ? q + (numerator < 0 ? -1 : 1) : q);
  }
}
