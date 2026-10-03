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

      // Said in words (M60): taking a picture off is now something Data
      // Lock asks a PIN for, and the prompt reads this line out.
      final label = await _labelOf(
        tx.selectOne,
        actor.firmId,
        ownerTable,
        ownerId,
      );
      for (final row in existing) {
        final id = row.read<String>('id');
        await tx.softDelete('attachments', id);
        tx.audit(
          action: photoRemovedAction,
          entityTable: 'attachments',
          entityId: id,
          summary: 'Picture taken off ${_said(ownerTable, label)}',
        );
      }
    });
  }

  // -------------------------------------------------------------------------
  // Photographs on entries (M60)
  // -------------------------------------------------------------------------

  /// Puts [image] on an entry beside whatever is there already, and returns
  /// its id.
  ///
  /// Not [attach]: an item has one photograph and a new one replaces it, but
  /// a supplier's bill of three pages is three photographs, and the deposit
  /// slip goes beside the cheque, not over it.
  ///
  /// Refused, in words, when the entry is not in these books or already
  /// carries [EntryPhoto.maxPerEntry]; refused outright, as [attach] is,
  /// when the picture is over [EntryPhoto.maxBytes] — a caller that skipped
  /// the reduction is a bug, not a shopkeeper's mistake.
  Future<String> addPhoto(
    ActorContext actor, {
    required EntryPhotoKind kind,
    required String ownerTable,
    required String ownerId,
    required ImageAttachment image,
    required String fileName,
  }) async {
    _requireEntryOwner(ownerTable);
    if (image.bytes.length > EntryPhoto.maxBytes) {
      throw ArgumentError.value(
        image.bytes.length,
        'image',
        'is ${image.bytes.length} bytes, over the ${EntryPhoto.maxBytes}-byte '
            'ceiling for a photograph of a paper. Reduce it first.',
      );
    }

    return _runner().run(actor, (tx) async {
      final label = await _labelOf(
        tx.selectOne,
        actor.firmId,
        ownerTable,
        ownerId,
      );
      if (label == null) {
        throw const PhotoRefused(
          'That entry is not in these books, so a photograph cannot be put '
          'on it.',
        );
      }
      final held = await tx.selectOne(
        'SELECT COUNT(*) AS n FROM attachments '
        'WHERE firm_id = ? AND owner_table = ? AND owner_id = ? '
        'AND deleted_at_utc IS NULL',
        [actor.firmId, ownerTable, ownerId],
      );
      if ((held?.read<int>('n') ?? 0) >= EntryPhoto.maxPerEntry) {
        throw const PhotoRefused(
          'This entry already has ${EntryPhoto.maxPerEntry} photographs. '
          'Take one off before adding another.',
        );
      }

      final id = await tx.insert('attachments', {
        'kind': kind.code,
        'owner_table': ownerTable,
        'owner_id': ownerId,
        'file_name': fileName,
        'mime_type': image.mimeType,
        'byte_size': image.bytes.length,
        'sha256': sha256.convert(image.bytes).toString(),
        'bytes': image.bytes,
        'width': image.width,
        'height': image.height,
      });
      tx.audit(
        action: photoAddedAction,
        entityTable: 'attachments',
        entityId: id,
        summary: 'Photo of the paper put on ${_said(ownerTable, label)}',
        after: {'owner_table': ownerTable, 'owner_id': ownerId},
      );
      return id;
    });
  }

  /// The photographs on one entry, oldest first, with those on the entries
  /// it corrected.
  ///
  /// A correction (M31, M36) is a new entry with a new number, and the old
  /// one is kept cancelled. The bijli bill photographed onto the first is
  /// still the bijli bill of the second, so the second shows it, marked as
  /// having come from the first; it stays where it was put, so the first
  /// shows it too.
  Future<List<EntryPhoto>> photosOf(
    String firmId,
    String ownerTable,
    String ownerId,
  ) async {
    if (!entryPhotoOwners.contains(ownerTable)) return const [];
    final owners = await _withEarlier(firmId, ownerTable, ownerId);
    final marks = List.filled(owners.length, '?').join(', ');
    final rows = await _db
        .customSelect(
          '''
          SELECT a.id, a.owner_id, a.kind, a.bytes, a.width, a.height,
                 a.created_at_utc, COALESCE(u.name, '') AS added_by
          FROM attachments a
          LEFT JOIN users u ON u.id = a.created_by
          WHERE a.firm_id = ? AND a.owner_table = ?
            AND a.owner_id IN ($marks)
            AND a.deleted_at_utc IS NULL AND a.bytes IS NOT NULL
          ORDER BY a.created_at_utc, a.id
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(ownerTable),
            for (final o in owners) Variable<String>(o),
          ],
          readsFrom: {_db.attachments, _db.users},
        )
        .get();
    return [
      for (final r in rows)
        EntryPhoto(
          id: r.read<String>('id'),
          ownerTable: ownerTable,
          ownerId: r.read<String>('owner_id'),
          kind: r.read<String>('kind'),
          bytes: r.read<Uint8List>('bytes'),
          width: r.readNullable<int>('width') ?? 0,
          height: r.readNullable<int>('height') ?? 0,
          addedAtUtc: DateTime.fromMillisecondsSinceEpoch(
            r.read<int>('created_at_utc'),
            isUtc: true,
          ),
          addedBy: r.read<String>('added_by'),
          fromEarlierEntry: r.read<String>('owner_id') != ownerId,
        ),
    ];
  }

  /// Takes one photograph off its entry, into the recycle bin.
  ///
  /// A tombstone, as everything here is: the picture stays in the books and
  /// comes back with one tap. Under Data Lock (M42) it asks for a PIN first,
  /// because the supplier's bill is exactly what somebody who meant harm
  /// would take off a purchase.
  Future<void> removePhoto(ActorContext actor, String photoId) => _runner().run(
    actor,
    (tx) async {
      final row = await tx.selectOne(
        'SELECT owner_table, owner_id, sha256 FROM attachments '
        'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
        [photoId, actor.firmId],
      );
      if (row == null) {
        throw const PhotoRefused('That photograph has already been taken off.');
      }
      final table = row.readNullable<String>('owner_table') ?? '';
      final owner = row.readNullable<String>('owner_id') ?? '';
      final label = await _labelOf(tx.selectOne, actor.firmId, table, owner);
      await tx.softDelete('attachments', photoId);
      tx.audit(
        action: photoRemovedAction,
        entityTable: 'attachments',
        entityId: photoId,
        summary: 'Photo taken off ${_said(table, label)}',
        before: {
          'owner_table': table,
          'owner_id': owner,
          'sha256': row.read<String>('sha256'),
        },
      );
    },
  );

  /// Every picture taken off something and not yet brought back, the latest
  /// first: entry photographs, and an item's photograph or the shop's logo
  /// removed by hand (M2, M51). A picture merely replaced by a newer one is
  /// not here — it was changed, not removed.
  ///
  /// Taken off twice, brought back between, it is listed once.
  Future<List<RemovedPhoto>> removedPhotos(
    String firmId, {
    int limit = 200,
  }) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT a.id, a.owner_table, a.owner_id, a.kind, a.bytes, a.sha256,
                 l.at_utc, COALESCE(u.name, '') AS removed_by,
                 CASE a.owner_table
                   WHEN 'documents' THEN (SELECT d.doc_no FROM documents d
                                          WHERE d.id = a.owner_id)
                   WHEN 'payments' THEN (SELECT p.payment_no FROM payments p
                                         WHERE p.id = a.owner_id)
                   WHEN 'parties' THEN (SELECT p.name FROM parties p
                                        WHERE p.id = a.owner_id)
                   WHEN 'items' THEN (SELECT i.name FROM items i
                                      WHERE i.id = a.owner_id)
                   -- M54: a loan's entry and a batch.
                   WHEN 'journal_entries' THEN (SELECT j.entry_no
                                                FROM journal_entries j
                                                WHERE j.id = a.owner_id)
                   WHEN 'stock_lots' THEN (SELECT l.lot_no FROM stock_lots l
                                           WHERE l.id = a.owner_id)
                 END AS owner_label
          FROM attachments a
          JOIN audit_log l
            ON l.firm_id = a.firm_id AND l.entity_table = 'attachments'
           AND l.entity_id = a.id AND l.action_code = ?
          LEFT JOIN users u ON u.id = l.created_by
          WHERE a.firm_id = ?
            AND a.deleted_at_utc IS NOT NULL AND a.bytes IS NOT NULL
            AND NOT EXISTS (
              SELECT 1 FROM attachments b
              WHERE b.firm_id = a.firm_id AND b.owner_table = a.owner_table
                AND b.owner_id = a.owner_id AND b.sha256 = a.sha256
                AND b.deleted_at_utc IS NULL)
          ORDER BY l.at_utc DESC, a.id DESC
          LIMIT ?
          ''',
          variables: [
            const Variable<String>(photoRemovedAction),
            Variable<String>(firmId),
            Variable<int>(limit),
          ],
          readsFrom: {
            _db.attachments,
            _db.auditLog,
            _db.users,
            _db.documents,
            _db.payments,
            _db.parties,
            _db.items,
          },
        )
        .get();
    final seen = <String>{};
    return [
      for (final r in rows)
        if (seen.add(
          '${r.read<String>('owner_table')}/${r.read<String>('owner_id')}/'
          '${r.read<String>('sha256')}',
        ))
          RemovedPhoto(
            id: r.read<String>('id'),
            ownerTable: r.readNullable<String>('owner_table') ?? '',
            ownerId: r.readNullable<String>('owner_id') ?? '',
            ownerLabel: r.readNullable<String>('owner_label') ?? '',
            kind: r.read<String>('kind'),
            bytes: r.read<Uint8List>('bytes'),
            removedAtUtc: DateTime.fromMillisecondsSinceEpoch(
              r.read<int>('at_utc'),
              isUtc: true,
            ),
            removedBy: r.read<String>('removed_by'),
          ),
    ];
  }

  /// Brings a removed picture back onto what it was taken off, and returns
  /// the id it now has.
  ///
  /// A tombstone is read-only — every other counter has been told it is
  /// gone — so what comes back is a new row carrying the same picture, the
  /// same kind and the same owner, and the activity log ties the two
  /// together. An item, the logo and the QR keep one picture each, so one
  /// of those coming back takes the place of whatever is there now, as
  /// changing it would.
  Future<String> restorePhoto(ActorContext actor, String removedId) =>
      _runner().run(actor, (tx) async {
        final was = await tx.selectOne(
          'SELECT kind, owner_table, owner_id, file_name, mime_type, '
          '       byte_size, sha256, bytes, width, height '
          'FROM attachments '
          'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NOT NULL '
          'AND bytes IS NOT NULL',
          [removedId, actor.firmId],
        );
        if (was == null) {
          throw const PhotoRefused(
            'That photograph is not in the recycle bin.',
          );
        }
        final table = was.readNullable<String>('owner_table') ?? '';
        final owner = was.readNullable<String>('owner_id') ?? '';
        final sha = was.read<String>('sha256');

        final twin = await tx.selectOne(
          'SELECT id FROM attachments WHERE firm_id = ? AND owner_table = ? '
          'AND owner_id = ? AND sha256 = ? AND deleted_at_utc IS NULL',
          [actor.firmId, table, owner, sha],
        );
        // Already back: brought back a moment ago, or the same picture put
        // on again by hand.
        if (twin != null) return twin.read<String>('id');

        final current = await tx.select(
          'SELECT id FROM attachments '
          'WHERE firm_id = ? AND owner_table = ? AND owner_id = ? '
          'AND deleted_at_utc IS NULL',
          [actor.firmId, table, owner],
        );
        if (entryPhotoOwners.contains(table)) {
          if (current.length >= EntryPhoto.maxPerEntry) {
            throw const PhotoRefused(
              'That entry already has ${EntryPhoto.maxPerEntry} photographs. '
              'Take one off before bringing this one back.',
            );
          }
        } else {
          for (final r in current) {
            await tx.softDelete('attachments', r.read<String>('id'));
          }
        }

        final id = await tx.insert('attachments', {
          'kind': was.read<String>('kind'),
          'owner_table': table,
          'owner_id': owner,
          'file_name': was.read<String>('file_name'),
          'mime_type': was.read<String>('mime_type'),
          'byte_size': was.read<int>('byte_size'),
          'sha256': sha,
          'bytes': was.read<Uint8List>('bytes'),
          'width': was.readNullable<int>('width'),
          'height': was.readNullable<int>('height'),
        });
        final label = await _labelOf(tx.selectOne, actor.firmId, table, owner);
        tx.audit(
          action: photoRestoredAction,
          entityTable: 'attachments',
          entityId: id,
          summary: 'Photo back on ${_said(table, label)}',
          before: {'restored_from': removedId},
        );
        return id;
      });

  static void _requireEntryOwner(String ownerTable) {
    if (!entryPhotoOwners.contains(ownerTable)) {
      throw ArgumentError.value(
        ownerTable,
        'ownerTable',
        'is not a table a photograph of a paper can be put on',
      );
    }
  }

  /// [ownerId] and every entry it corrected, back to the first.
  ///
  /// A bill corrected at the counter (M36) is linked `revises` from the old
  /// to the new; a payment, charge, expense or other income corrected by
  /// hand (M31, M47) leaves an `*_EDITED` row naming the old in its
  /// `before_json`. Followed back a bounded number of steps — nobody
  /// corrects one entry sixteen times, and a loop in the links must not
  /// hang a page.
  Future<List<String>> _withEarlier(
    String firmId,
    String ownerTable,
    String ownerId,
  ) async {
    final found = <String>[ownerId];
    var frontier = [ownerId];
    for (var step = 0; step < 16 && frontier.isNotEmpty; step++) {
      final marks = List.filled(frontier.length, '?').join(', ');
      final ids = [for (final f in frontier) Variable<String>(f)];
      final earlier = <String>[];
      if (ownerTable == 'documents') {
        final links = await _db
            .customSelect(
              'SELECT from_document_id AS id FROM doc_links '
              "WHERE firm_id = ? AND link_type = 'revises' "
              'AND deleted_at_utc IS NULL AND to_document_id IN ($marks)',
              variables: [Variable<String>(firmId), ...ids],
              readsFrom: {_db.docLinks},
            )
            .get();
        earlier.addAll(links.map((r) => r.read<String>('id')));
      }
      final edits = await _db
          .customSelect(
            "SELECT json_extract(before_json, '\$.id') AS id FROM audit_log "
            'WHERE firm_id = ? AND entity_table = ? '
            "AND action_code IN ('PAYMENT_EDITED', 'CHARGE_EDITED', "
            "'EXPENSE_EDITED', 'OTHER_INCOME_EDITED') "
            'AND entity_id IN ($marks)',
            variables: [
              Variable<String>(firmId),
              Variable<String>(ownerTable),
              ...ids,
            ],
            readsFrom: {_db.auditLog},
          )
          .get();
      earlier.addAll([for (final r in edits) ?r.readNullable<String>('id')]);
      frontier = [
        for (final id in earlier)
          if (!found.contains(id)) id,
      ];
      found.addAll(frontier);
    }
    return found;
  }

  /// What a row is called, or null when it is not in [firmId]'s books.
  /// Pictures on the shop itself (the logo, the QR) have no name to give.
  static Future<String?> _labelOf(
    Future<QueryRow?> Function(String sql, [List<Object?> args]) selectOne,
    String firmId,
    String table,
    String id,
  ) async {
    final column = switch (table) {
      'documents' => 'doc_no',
      'payments' => 'payment_no',
      'parties' || 'items' => 'name',
      'journal_entries' => 'entry_no', // M54: a loan's entry
      'stock_lots' => 'lot_no', // M54: a batch
      _ => null,
    };
    if (column == null) return '';
    final row = await selectOne(
      'SELECT $column AS label FROM $table WHERE id = ? AND firm_id = ?',
      [id, firmId],
    );
    return row?.readNullable<String>('label');
  }

  /// "entry PUR-0012", "payment RCV-0004", "the khata of Rashid Traders",
  /// for the activity log's one line and the Data Lock prompt.
  static String _said(String table, String? label) => switch (table) {
    'documents' => 'entry ${label ?? ''}',
    'payments' => 'payment ${label ?? ''}',
    'parties' => 'the khata of ${label ?? ''}',
    'items' => 'item ${label ?? ''}',
    'journal_entries' => 'entry ${label ?? ''}', // M54
    'stock_lots' => 'batch ${label ?? ''}', // M54
    _ => 'the shop',
  };
}
