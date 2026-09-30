import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// Which price a buyer pays.
void main() {
  ItemSummary oil({Rate? wholesale, Rate? vip}) => ItemSummary(
    id: 'oil',
    name: 'Cooking Oil 5L',
    unitId: 'pcs',
    unitCode: 'pcs',
    unitDecimals: 0,
    saleRate: Rate.rupees(2500),
    wholesaleRate: wholesale,
    vipRate: vip,
    stockOnHand: Qty.units(10),
    minStock: Qty.zero,
    tracksStock: true,
  );

  group('the price a buyer pays', () {
    test('a retail buyer pays the shelf price', () {
      expect(
        priceFor(oil(wholesale: Rate.rupees(2300)), PriceTier.retail),
        Rate.rupees(2500),
      );
    });

    test('a wholesale buyer pays the trade price', () {
      expect(
        priceFor(oil(wholesale: Rate.rupees(2300)), PriceTier.wholesale),
        Rate.rupees(2300),
      );
    });

    test('an item with no trade price is sold to everybody at one price', () {
      expect(priceFor(oil(), PriceTier.wholesale), Rate.rupees(2500));
    });

    test('a VIP buyer pays the VIP price', () {
      expect(
        priceFor(
          oil(wholesale: Rate.rupees(2300), vip: Rate.rupees(2200)),
          PriceTier.vip,
        ),
        Rate.rupees(2200),
      );
    });

    test('a VIP buyer falls back to the trade price, then the shelf price', () {
      expect(
        priceFor(oil(wholesale: Rate.rupees(2300)), PriceTier.vip),
        Rate.rupees(2300),
      );
      expect(priceFor(oil(), PriceTier.vip), Rate.rupees(2500));
    });

    test('a tier nobody recognises is retail', () {
      expect(PriceTier.parse('platinum'), PriceTier.retail);
      expect(PriceTier.parse('vip'), PriceTier.vip);
      expect(PriceTier.parse(null), PriceTier.retail);
      expect(PriceTier.parse('wholesale'), PriceTier.wholesale);
    });
  });
}
