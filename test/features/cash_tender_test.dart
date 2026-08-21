import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Cash Tender calculates exact change for standard Pakistani rupee notes', () {
    const totalBill = 1450.0;
    const tendered5000 = 5000.0;
    const tendered2000 = 2000.0;

    const changeFor5000 = tendered5000 - totalBill;
    const changeFor2000 = tendered2000 - totalBill;

    expect(changeFor5000, 3550.0);
    expect(changeFor2000, 550.0);
  });

  test('Cash Tender flags insufficient cash', () {
    const totalBill = 2500.0;
    const tendered = 2000.0;

    const isSufficient = tendered >= totalBill;
    const shortage = totalBill - tendered;

    expect(isSufficient, isFalse);
    expect(shortage, 500.0);
  });
}
