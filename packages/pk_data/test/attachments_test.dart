import 'dart:typed_data';

import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// Pictures, stored inline in the shop's own database.
///
/// The schema chose this over a file path and says why: "small images live
/// inline so a backup is one file and a restore cannot come back with missing
/// pictures". A path would be faster and would mean a shopkeeper restoring
/// onto a new phone gets their books back with every photograph gone — which
/// reads as the restore having half worked, and is exactly the kind of thing
/// that stops people trusting backups at all.
///
/// That trade only holds while the pictures stay small, so the ceiling is not
/// a nicety. It is the thing that keeps the choice honest.
void main() {
  late AppDatabase db;
  late FixedClock clock;
  late UlidGenerator ids;
  late TxRunner runner;
  late FirstRunResult firm;
  late ActorContext actor;
  late DriftAttachments attachments;
  late String itemId;

  /// Bytes that are not a real JPEG, which is fine: this layer stores what it
  /// is handed and the shrinker is what decides whether it is a picture.
  Uint8List blob(int size, [int fill = 7]) =>
      Uint8List.fromList(List.filled(size, fill));

  ImageAttachment image(Uint8List bytes) => ImageAttachment(
    id: 'ignored',
    bytes: bytes,
    mimeType: 'image/jpeg',
    width: 512,
    height: 384,
  );

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
    attachments = DriftAttachments(db, () => runner);

    final pcs =
        (await db
                .customSelect("SELECT id FROM units WHERE code = 'pcs'")
                .getSingle())
            .read<String>('id');
    itemId = await DriftCatalogueWriter(runner).addItem(
      actor,
      ItemDraft(
        name: 'Cooking Oil 5L',
        baseUnitId: pcs,
        saleRate: Rate.rupees(1450),
      ),
    );
  });

  tearDown(() async => db.close());

  Future<String> attach(Uint8List bytes) => attachments.attach(
    actor,
    kind: 'item_image',
    ownerTable: 'items',
    ownerId: itemId,
    image: image(bytes),
    fileName: 'oil.jpg',
  );

  test('a picture goes in and comes back byte for byte', () async {
    // A blob that survives a round trip is the whole point: the write path
    // refused anything but int, String, bool and null until this landed, and
    // a silently-truncated picture would look like a working feature.
    final bytes = blob(4096);
    await attach(bytes);

    final loaded = await attachments.forOwner(firm.firmId, 'items', itemId);
    expect(loaded, isNotNull);
    expect(loaded!.bytes, bytes);
    expect(loaded.mimeType, 'image/jpeg');
    expect(loaded.width, 512);
    expect(loaded.height, 384);
  });

  test('an item with no picture is not an error', () async {
    expect(await attachments.forOwner(firm.firmId, 'items', itemId), isNull);
  });

  test('replacing a picture leaves one, not two', () async {
    // A shopkeeper changing an item photograph means the old one is gone. The
    // alternative is a database that accumulates every photograph ever taken
    // of a tin of oil, in a product whose backup IS the database.
    await attach(blob(2048, 1));
    await attach(blob(2048, 2));

    final loaded = await attachments.forOwner(firm.firmId, 'items', itemId);
    expect(loaded!.bytes.first, 2);

    final live = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM attachments '
          'WHERE owner_id = ? AND deleted_at_utc IS NULL',
          variables: [Variable<String>(itemId)],
        )
        .getSingle();
    expect(live.read<int>('n'), 1);
  });

  test('a replaced picture is tombstoned, never destroyed', () async {
    // This product does not delete rows. The old picture stays as a tombstone
    // so the sync outbox has something coherent to carry to another till.
    await attach(blob(1024, 1));
    await attach(blob(1024, 2));

    final all = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM attachments WHERE owner_id = ?',
          variables: [Variable<String>(itemId)],
        )
        .getSingle();
    expect(all.read<int>('n'), 2);
  });

  test('removing a picture leaves the item alone', () async {
    await attach(blob(1024));
    await attachments.detach(actor, ownerTable: 'items', ownerId: itemId);

    expect(await attachments.forOwner(firm.firmId, 'items', itemId), isNull);
    final item = await DriftAppQueries(db).itemById(firm.firmId, itemId);
    expect(item, isNotNull, reason: 'the item went with the picture');
  });

  test('removing a picture that is not there is not an error', () async {
    await attachments.detach(actor, ownerTable: 'items', ownerId: itemId);
    expect(await attachments.forOwner(firm.firmId, 'items', itemId), isNull);
  });

  test('an oversized picture is refused, and says why', () async {
    // Refused rather than stored. One picture over the ceiling is not one bad
    // row — it is a backup that has quietly stopped being something a
    // shopkeeper can send over WhatsApp, which is how this product expects
    // backups to travel.
    await expectLater(
      attach(blob(ImageAttachment.maxBytes + 1)),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('ceiling'),
        ),
      ),
    );
    expect(await attachments.forOwner(firm.firmId, 'items', itemId), isNull);
  });

  test('a picture exactly at the ceiling is allowed', () async {
    await attach(blob(ImageAttachment.maxBytes));
    final loaded = await attachments.forOwner(firm.firmId, 'items', itemId);
    expect(loaded!.bytes.length, ImageAttachment.maxBytes);
  });

  test('the picture is content-addressed', () async {
    // So a later pass can tell two identical pictures from two different ones
    // without comparing megabytes.
    await attach(blob(2048));
    final row = await db
        .customSelect(
          'SELECT sha256, byte_size FROM attachments '
          'WHERE owner_id = ? AND deleted_at_utc IS NULL',
          variables: [Variable<String>(itemId)],
        )
        .getSingle();
    expect(row.read<String>('sha256'), hasLength(64));
    expect(row.read<int>('byte_size'), 2048);
  });

  test('adding a picture is audited like every other change', () async {
    await attach(blob(1024));
    final audit = await db
        .customSelect(
          'SELECT action_code FROM audit_log WHERE action_code = ?',
          variables: [Variable<String>('ATTACHMENT_ADDED')],
        )
        .get();
    expect(audit, hasLength(1));
  });

  test('another firm cannot see this shop pictures', () async {
    await attach(blob(1024));
    expect(
      await attachments.forOwner('SOME-OTHER-FIRM', 'items', itemId),
      isNull,
    );
  });

  test('the books still balance afterwards', () async {
    // A picture writes no journal entry, and this asserts that staying true.
    await attach(blob(2048));
    final health = await db.checkHealth();
    expect(health.isHealthy, isTrue, reason: health.toString());
  });
}
