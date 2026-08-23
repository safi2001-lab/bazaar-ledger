import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';
import 'tx_runner.dart';

/// Pictures, stored inline in the database.
///
/// The schema's own comment explains the choice: "small images live inline so a
/// backup is one file and a restore cannot come back with missing pictures".
/// A path would be faster and would mean a shopkeeper who restores onto a new
/// phone gets their books back with every photograph gone — which reads as the
/// restore having half worked, and is the kind of thing that stops people
/// trusting backups at all.
///
/// It only holds up while the pictures stay small, which is what the shrinker
/// and the size ceiling are for.
final class DriftAttachments implements AttachmentStore {
  DriftAttachments(this._db, this._runner);

  final AppDatabase _db;

  /// Asked for each time rather than held: the bootstrap rebuilds its runner
  /// once first run registers the device, and a cached one would keep stamping
  /// rows with the placeholder node id.
  final TxRunner Function() _runner;

  @override
  Future<String> attach(
    ActorContext actor, {
    required String kind,
    required String ownerTable,
    required String ownerId,
    required ImageAttachment image,
    required String fileName,
  }) async {
    if (image.bytes.length > ImageAttachment.maxBytes) {
      throw ArgumentError.value(
        image.bytes.length,
        'image',
        'is ${image.bytes.length} bytes, over the '
            '${ImageAttachment.maxBytes}-byte ceiling. Refused rather than '
            'stored: one oversized picture is not one bad row, it is a backup '
            'that has quietly stopped being something a shopkeeper can send '
            'over WhatsApp.',
      );
    }

    return _runner().run(actor, (tx) async {
      // One picture per owner. A shopkeeper replacing an item's photograph
      // means the old one is gone, not that the shop accumulates every
      // photograph ever taken of a tin of oil.
      final existing = await tx.select(
        'SELECT id FROM attachments '
        'WHERE firm_id = ? AND owner_table = ? AND owner_id = ? '
        'AND deleted_at_utc IS NULL',
        [actor.firmId, ownerTable, ownerId],
      );
      for (final row in existing) {
        await tx.softDelete('attachments', row.read<String>('id'));
      }

      final id = await tx.insert('attachments', {
        'kind': kind,
        'owner_table': ownerTable,
        'owner_id': ownerId,
        'file_name': fileName,
        'mime_type': image.mimeType,
        'byte_size': image.bytes.length,
        // Content-addressed, so a later pass can tell two identical pictures
        // apart from two different ones without comparing megabytes.
        'sha256': sha256.convert(image.bytes).toString(),
        'bytes': image.bytes,
        'width': image.width,
        'height': image.height,
      });

      tx.audit(
        action: 'ATTACHMENT_ADDED',
        entityTable: 'attachments',
        entityId: id,
        summary: '$kind for $ownerTable ${image.width}x${image.height}',
      );
      return id;
    });
  }

  @override
  Future<ImageAttachment?> forOwner(
    String firmId,
    String ownerTable,
    String ownerId,
  ) async {
    final row = await _db
        .customSelect(
          'SELECT id, bytes, mime_type, width, height FROM attachments '
          'WHERE firm_id = ? AND owner_table = ? AND owner_id = ? '
          'AND deleted_at_utc IS NULL '
          'ORDER BY created_at_utc DESC LIMIT 1',
          variables: [
            Variable<String>(firmId),
            Variable<String>(ownerTable),
            Variable<String>(ownerId),
          ],
        )
        .getSingleOrNull();
    if (row == null) return null;

    final bytes = row.readNullable<Uint8List>('bytes');
    // A row with a storage_path and no inline bytes is legal in the schema and
    // not something this build writes. Reported as "no picture" rather than as
    // an error: the item screen then offers to add one, which is the action
    // that fixes it.
    if (bytes == null) return null;

    return ImageAttachment(
      id: row.read<String>('id'),
      bytes: bytes,
      mimeType: row.read<String>('mime_type'),
      width: row.readNullable<int>('width') ?? 0,
      height: row.readNullable<int>('height') ?? 0,
    );
  }

  @override
  Future<void> detach(
    ActorContext actor, {
    required String ownerTable,
    required String ownerId,
  }) async {
    await _runner().run(actor, (tx) async {
      final existing = await tx.select(
        'SELECT id FROM attachments '
        'WHERE firm_id = ? AND owner_table = ? AND owner_id = ? '
        'AND deleted_at_utc IS NULL',
        [actor.firmId, ownerTable, ownerId],
      );
      if (existing.isEmpty) return;

      for (final row in existing) {
        final id = row.read<String>('id');
        await tx.softDelete('attachments', id);
        tx.audit(
          action: 'ATTACHMENT_REMOVED',
          entityTable: 'attachments',
          entityId: id,
        );
      }
    });
  }
}
