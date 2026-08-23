import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// Finding a packet by whatever read its barcode.
///
/// A shop scans the same tin with a USB wedge in the morning and the phone
/// camera in the afternoon. The wedge sends twelve digits; ML Kit sends
/// thirteen, because UPC-A formally IS an EAN-13 with a leading zero.
///
/// With an exact-match lookup that means the item is found one way and not the
/// other — and the failure looks nothing like a normalisation problem. It
/// looks like the item is missing. So the cashier adds it again by hand, and
/// the catalogue ends up carrying one packet twice, at two prices, with the
/// stock split between them and neither figure right.
void main() {
  late AppDatabase db;
  late FixedClock clock;
  late UlidGenerator ids;
  late TxRunner runner;
  late FirstRunResult firm;
  late ActorContext actor;
  late DriftCatalogueWriter catalogue;
  late DriftAppQueries queries;
  late String pcs;

  setUp(() async {
    db = await openTestDatabase();
    clock = FixedClock(DateTime.utc(2026, 8, 24, 9));
    ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    actor = firm.actorAt(clock.nowUtc());
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    catalogue = DriftCatalogueWriter(runner);
    queries = DriftAppQueries(db);
    pcs =
        (await db
                .customSelect("SELECT id FROM units WHERE code = 'pcs'")
                .getSingle())
            .read<String>('id');
  });

  tearDown(() async => db.close());

  Future<String> stock(String name, String? barcode) => catalogue.addItem(
    actor,
    ItemDraft(
      name: name,
      barcode: barcode,
      baseUnitId: pcs,
      saleRate: Rate.rupees(500),
    ),
  );

  test('a packet entered as UPC is found when a camera reads EAN-13', () async {
    // The shopkeeper typed the twelve digits printed under the bars. The phone
    // reports thirteen. Same packet.
    await stock('Cooking Oil 5L', '012345678905');

    final found = await queries.itemByBarcode(firm.firmId, '0012345678905');
    expect(
      found,
      isNotNull,
      reason:
          'the camera cannot find a packet the wedge can, so the cashier '
          'adds it again and the catalogue carries it twice',
    );
    expect(found!.name, 'Cooking Oil 5L');
  });

  test('a packet entered as EAN-13 is found when a wedge reads UPC', () async {
    await stock('Cooking Oil 5L', '0012345678905');

    final found = await queries.itemByBarcode(firm.firmId, '012345678905');
    expect(found, isNotNull);
    expect(found!.name, 'Cooking Oil 5L');
  });

  test('the exact code wins when both forms exist as separate items', () async {
    // Rare and real. If a shop genuinely has both, the one the scanner read is
    // the right answer — an inferred variant must never outrank it.
    await stock('Twelve', '012345678905');
    await stock('Thirteen', '0012345678905');

    expect(
      (await queries.itemByBarcode(firm.firmId, '012345678905'))!.name,
      'Twelve',
    );
    expect(
      (await queries.itemByBarcode(firm.firmId, '0012345678905'))!.name,
      'Thirteen',
    );
  });

  test('a Pakistani EAN-13 is matched exactly, never widened', () async {
    // 896 is Pakistan. It has no UPC form, and inventing one would match the
    // wrong packet.
    await stock('Chawal 5kg', '8964000999999');

    expect(
      await queries.itemByBarcode(firm.firmId, '8964000999999'),
      isNotNull,
    );
    expect(await queries.itemByBarcode(firm.firmId, '964000999999'), isNull);
  });

  test('a shop code is matched exactly', () async {
    await stock('Loose Cheeni', 'CHEENI-LOOSE');
    expect(await queries.itemByBarcode(firm.firmId, 'CHEENI-LOOSE'), isNotNull);
    expect(await queries.itemByBarcode(firm.firmId, 'CHEENI'), isNull);
  });

  test('a code nobody has is not found, and is not an error', () async {
    await stock('Cooking Oil 5L', '012345678905');
    expect(await queries.itemByBarcode(firm.firmId, '999999999999'), isNull);
  });

  test('nothing scanned finds nothing', () async {
    await stock('Cooking Oil 5L', '012345678905');
    expect(await queries.itemByBarcode(firm.firmId, ''), isNull);
    expect(await queries.itemByBarcode(firm.firmId, '   '), isNull);
  });

  test('an archived packet does not come back onto a bill', () async {
    final id = await stock('Old stock', '012345678905');
    await catalogue.archiveItem(actor, id);
    expect(await queries.itemByBarcode(firm.firmId, '0012345678905'), isNull);
  });

  test('another shop barcode is not this shop item', () async {
    await stock('Cooking Oil 5L', '012345678905');
    expect(
      await queries.itemByBarcode('SOME-OTHER-FIRM', '012345678905'),
      isNull,
    );
  });
}
