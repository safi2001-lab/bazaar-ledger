class TajirDostTaxResult {
  final double grossTurnover;
  final double advanceTaxRate; // 1.0%
  final double grossTaxLiability;
  final double electricityWhtDeductions;
  final double netPayableTax;
  final double carriedForwardCredit;

  TajirDostTaxResult({
    required this.grossTurnover,
    this.advanceTaxRate = 1.0,
    required this.grossTaxLiability,
    required this.electricityWhtDeductions,
    required this.netPayableTax,
    required this.carriedForwardCredit,
  });
}

class TajirDostEngine {
  /// Calculates monthly Tajir Dost 1% Advance Tax and offsets Section 235 Electricity WHT
  static TajirDostTaxResult calculateMonthlyTax({
    required double monthlyTurnover,
    required double monthlyElectricityWht,
    double advanceTaxRate = 1.0, // 1% default
  }) {
    final grossLiability = monthlyTurnover * (advanceTaxRate / 100.0);

    if (monthlyElectricityWht >= grossLiability) {
      return TajirDostTaxResult(
        grossTurnover: monthlyTurnover,
        advanceTaxRate: advanceTaxRate,
        grossTaxLiability: grossLiability,
        electricityWhtDeductions: monthlyElectricityWht,
        netPayableTax: 0.0,
        carriedForwardCredit: monthlyElectricityWht - grossLiability,
      );
    } else {
      return TajirDostTaxResult(
        grossTurnover: monthlyTurnover,
        advanceTaxRate: advanceTaxRate,
        grossTaxLiability: grossLiability,
        electricityWhtDeductions: monthlyElectricityWht,
        netPayableTax: grossLiability - monthlyElectricityWht,
        carriedForwardCredit: 0.0,
      );
    }
  }
}
