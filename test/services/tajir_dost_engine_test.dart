import 'package:flutter_test/flutter_test.dart';
import 'package:pakistan_sme_billing/services/tajir_dost_engine.dart';

void main() {
  test('TajirDostEngine calculates 1% turnover tax and offsets partial electricity WHT', () {
    // Monthly sales Rs 10 Lakh -> 1% tax = Rs 10,000.
    // Electricity WHT = Rs 4,000.
    // Net Payable = Rs 6,000.
    final result = TajirDostEngine.calculateMonthlyTax(
      monthlyTurnover: 1000000.0,
      monthlyElectricityWht: 4000.0,
    );

    expect(result.grossTaxLiability, 10000.0);
    expect(result.electricityWhtDeductions, 4000.0);
    expect(result.netPayableTax, 6000.0);
    expect(result.carriedForwardCredit, 0.0);
  });

  test('TajirDostEngine handles excess electricity WHT and carries credit forward', () {
    // Monthly sales Rs 2 Lakh -> 1% tax = Rs 2,000.
    // Electricity WHT = Rs 3,500.
    // Net Payable = 0. Carried credit = Rs 1,500.
    final result = TajirDostEngine.calculateMonthlyTax(
      monthlyTurnover: 200000.0,
      monthlyElectricityWht: 3500.0,
    );

    expect(result.grossTaxLiability, 2000.0);
    expect(result.netPayableTax, 0.0);
    expect(result.carriedForwardCredit, 1500.0);
  });
}
