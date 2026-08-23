import 'package:pk_money/pk_money.dart';

/// The kinds of tax a single line can carry.
///
/// One line can carry several at once, each with its own base — a 3rd Schedule
/// item is taxed on its printed retail price while further tax is charged on
/// the sale value, so these cannot collapse into one column.
enum TaxKind {
  salesTax,
  furtherTax,
  extraTax,
  withholding,
  provincialSt,
  fed,
  cess;

  /// The value stored in `document_line_taxes.tax_kind`.
  String get code => switch (this) {
        TaxKind.salesTax => 'sales_tax',
        TaxKind.furtherTax => 'further_tax',
        TaxKind.extraTax => 'extra_tax',
        TaxKind.withholding => 'withholding',
        TaxKind.provincialSt => 'provincial_st',
        TaxKind.fed => 'fed',
        TaxKind.cess => 'cess',
      };
}

/// One tax applied to one line.
final class TaxCharge {
  const TaxCharge({
    required this.kind,
    required this.code,
    required this.rateBp,
    required this.base,
    required this.amount,
    this.ruleId,
    this.isInclusive = false,
    this.sroScheduleNo,
    this.sroItemNo,
  });

  final TaxKind kind;

  /// The rule's short code, e.g. `ST_STD_18` or `FURTHER_4`.
  final String code;

  /// Basis points. 18% is 1800; further tax at 4% is 400; the 8th Schedule's
  /// 8.5% and 12.75% are 850 and 1275 and stay exact.
  final int rateBp;

  final Money base;
  final Money amount;

  final String? ruleId;
  final bool isInclusive;
  final String? sroScheduleNo;
  final String? sroItemNo;
}

/// Everything the tax rules need to know about the sale as a whole.
final class TaxContext {
  const TaxContext({
    required this.isSellerRegistered,
    required this.buyerIsRegistered,
    required this.buyerIsOnAtl,
    required this.province,
    required this.pricesIncludeTax,
    required this.ruleVersion,
  });

  /// Most kiryana stores are not registered. Under s.3(9) STA a non-Tier-1
  /// retailer pays sales tax through the electricity bill instead, so the
  /// whole compliance path must be optional and must not gate the product.
  final bool isSellerRegistered;

  final bool buyerIsRegistered;

  /// Further tax under s.3(1A) STA, verified against the Act as amended to
  /// 30 June 2026.
  ///
  /// The operative words are "where taxable supplies are made to a person who
  /// has not obtained registration number **or** he is not an active
  /// taxpayer". The two limbs are disjunctive, so EITHER triggers it: the
  /// "not an active taxpayer" limb was added by the Finance Act 2022 and the
  /// rate went from three per cent to four by the Finance Act 2023.
  ///
  /// So [buyerIsRegistered] and this field are both inputs to the charge. The
  /// previous specification had it as registration alone, which under-charges
  /// a registered buyer who has fallen off the list; reading it as ATL alone
  /// under-charges an unregistered one. `null` here means nobody has checked,
  /// which is not the same as being on the list — and the engine treats it as
  /// off, because the shopkeeper pays the difference either way.
  final bool? buyerIsOnAtl;

  final String province;
  final bool pricesIncludeTax;

  /// Which effective-dated rule pack computed this. Stored on the document so
  /// a reprint next year still shows this year's rates.
  final String ruleVersion;
}

/// Computes the taxes on one line.
///
/// The real rule pack lands in M12. Everything before it ships with
/// [UntaxedEngine], which is the correct behaviour for the majority of the
/// market rather than a placeholder.
abstract interface class TaxEngine {
  List<TaxCharge> chargesFor({
    required Money taxableBase,
    required Money? mrp,
    required String? itemTaxRuleId,
    required bool isThirdSchedule,
    required TaxContext context,
  });

  /// The rule pack version stamped onto documents this engine computes.
  String get ruleVersion;
}

/// Charges nothing.
///
/// This is not a stub. An unregistered kiryana store charges no sales tax, and
/// that is what the overwhelming majority of the addressable market is: FBR
/// e-invoicing binds sales-tax-registered persons, and most corner shops are
/// not registered persons.
final class UntaxedEngine implements TaxEngine {
  const UntaxedEngine();

  @override
  String get ruleVersion => 'untaxed-v1';

  @override
  List<TaxCharge> chargesFor({
    required Money taxableBase,
    required Money? mrp,
    required String? itemTaxRuleId,
    required bool isThirdSchedule,
    required TaxContext context,
  }) =>
      const [];
}
