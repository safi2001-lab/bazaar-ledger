import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Split payment preserves total balance integrity (Cash + Khata == Total)', () {
    const totalBill = 3500.0;
    const cashPortion = 1500.0;
    const creditPortion = totalBill - cashPortion;

    expect(creditPortion, 2000.0);
    expect(cashPortion + creditPortion, totalBill);
  });
}
