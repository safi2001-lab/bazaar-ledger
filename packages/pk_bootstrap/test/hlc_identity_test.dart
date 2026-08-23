import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

void main() {
  test('every row written after setup names this device in its HLC', () async {
    final services = await openInMemoryServices();
    addTearDown(services.close);

    await services.setUpShop(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
    );

    final firm = (await services.queries.currentFirm())!;
    final units = await services.queries.units(firm.id);
    await services.catalogue.addItem(
      services.actorNow(),
      ItemDraft(
        name: 'Cooking Oil 5L',
        baseUnitId: units.firstWhere((u) => u.code == 'pcs').id,
        saleRate: const Rate.rupees(2500),
      ),
    );

    final rows = await services.database
        .customSelect('SELECT DISTINCT hlc FROM items')
        .get();
    final hlcs = rows.map((r) => r.read<String>('hlc')).toList();

    expect(hlcs, isNotEmpty);
    for (final hlc in hlcs) {
      expect(
        hlc.endsWith('-unregistered'),
        isFalse,
        reason: 'the HLC node id is still the bootstrap placeholder: $hlc',
      );
    }
  });
}
