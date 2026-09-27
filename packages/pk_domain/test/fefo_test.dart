import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

LotBalance _lot(String no, int units, String? expiry) => LotBalance(
  lotId: 'L-$no',
  lotNo: no,
  qty: Qty.units(units),
  expiry: expiry == null ? null : BusinessDate(expiry),
);

const _today = BusinessDate('2026-09-26');

void main() {
  group('fefo', () {
    test('the batch that expires first goes first', () {
      final takes = takeFefo(
        needed: Qty.units(15),
        lots: [_lot('B2', 20, '2027-06-30'), _lot('B1', 10, '2026-12-31')],
        unlotted: Qty.zero,
        today: _today,
      );
      expect(takes, [
        (lotId: 'L-B1', qty: Qty.units(10)),
        (lotId: 'L-B2', qty: Qty.units(5)),
      ]);
    });

    test('an expired batch is never taken, and the sale is refused', () {
      expect(
        () => takeFefo(
          needed: Qty.units(5),
          lots: [_lot('OLD', 10, '2026-09-01'), _lot('NEW', 2, '2027-01-31')],
          unlotted: Qty.zero,
          today: _today,
        ),
        throwsA(
          isA<StockRefused>().having(
            (e) => e.reason,
            'reason',
            contains('Batch OLD expired on 2026-09-01'),
          ),
        ),
      );
    });

    test('stock in no batch goes after every batch', () {
      final takes = takeFefo(
        needed: Qty.units(8),
        lots: [_lot('B1', 5, '2027-01-31')],
        unlotted: Qty.units(10),
        today: _today,
      );
      expect(takes, [
        (lotId: 'L-B1', qty: Qty.units(5)),
        (lotId: null, qty: Qty.units(3)),
      ]);
    });

    test('a batch expiring today can still be sold today', () {
      final takes = takeFefo(
        needed: Qty.units(1),
        lots: [_lot('B1', 5, '2026-09-26')],
        unlotted: Qty.zero,
        today: _today,
      );
      expect(takes.single.lotId, 'L-B1');
    });
  });
}
