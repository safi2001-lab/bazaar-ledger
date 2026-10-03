import 'package:drift/drift.dart' show QueryRow;
import 'package:pk_domain/pk_domain.dart';

import 'drift_purchase_return_writer.dart';
import 'tx_runner.dart';

/// The pharmacy pack's writes (M49): a batch put on hold and let go again,
/// the shop's standing discount off the printed price, the Schedule register
/// kept as a bill posts, and an expiry return to one supplier written in one
/// transaction.
///
/// Everything goes through [TxRunner], so each is audited, carried to the
/// other counters, and held to the owner's closed books.
final class DriftPharmacyWriter {
  const DriftPharmacyWriter(this._runner);

  final TxRunner _runner;

  /// Puts batch [lotId] on hold for [reason]: first-expiry-first-out passes
  /// it by, and the counter refuses it in these words, until it is let go.
  Future<void> holdBatch(ActorContext actor, String lotId, String reason) {
    final why = reason.trim();
    if (why.isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'a hold has to say why');
    }
    return _runner.run(actor, (tx) async {
      final lot = await _lot(tx, lotId);
      final was = lot.readNullable<String>('hold_reason');
      if (was == why) return;
      await tx.update('stock_lots', lotId, {'hold_reason': why});
      tx.audit(
        action: 'BATCH_HELD',
        entityTable: 'stock_lots',
        entityId: lotId,
        summary:
            'Batch ${lot.read<String>('lot_no')} of '
            '${lot.read<String>('item_name')} put on hold: $why',
        before: {'hold_reason': was},
        after: {'hold_reason': why},
      );
    });
  }

  /// Lets batch [lotId] be sold again.
  Future<void> releaseBatch(ActorContext actor, String lotId) =>
      _runner.run(actor, (tx) async {
        final lot = await _lot(tx, lotId);
        final was = lot.readNullable<String>('hold_reason');
        if (was == null) return;
        await tx.update('stock_lots', lotId, {'hold_reason': null});
        tx.audit(
          action: 'BATCH_RELEASED',
          entityTable: 'stock_lots',
          entityId: lotId,
          summary:
              'Batch ${lot.read<String>('lot_no')} of '
              '${lot.read<String>('item_name')} back on sale',
          before: {'hold_reason': was},
          after: {'hold_reason': null},
        );
      });

  Future<QueryRow> _lot(Tx tx, String lotId) async {
    final row = await tx.selectOne(
      'SELECT l.lot_no, l.hold_reason, i.name AS item_name '
      'FROM stock_lots l JOIN items i ON i.id = l.item_id '
      'WHERE l.id = ? AND l.firm_id = ? AND l.deleted_at_utc IS NULL',
      [lotId, tx.actor.firmId],
    );
    if (row == null) throw StateError('No batch $lotId in this shop.');
    return row;
  }

  /// Sets the shop's standing discount off the printed price, in basis
  /// points: 1000 is "10% off on all medicines", 0 is none.
  Future<void> setOffMrp(ActorContext actor, int bp) {
    if (bp < 0 || bp > 10000) {
      throw ArgumentError.value(bp, 'bp', 'must be between 0 and 10000');
    }
    return _runner.run(actor, (tx) async {
      final held = await tx.selectOne(
        'SELECT id, setting_value FROM settings '
        'WHERE firm_id = ? AND setting_key = ? AND deleted_at_utc IS NULL',
        [actor.firmId, offMrpSettingKey],
      );
      final was = held?.read<String>('setting_value');
      if (was == '$bp') return;
      if (held == null) {
        // An id worked out from the shop's, as the shelf rule's is (M53):
        // the owner setting it on two phones apart writes one row twice,
        // and the merge keeps the later.
        await tx.insert('settings', {
          'setting_key': offMrpSettingKey,
          'setting_value': '$bp',
          'value_type': 'int',
        }, id: 'off-mrp-${actor.firmId}');
      } else {
        await tx.update('settings', held.read<String>('id'), {
          'setting_value': '$bp',
        });
      }
      tx.audit(
        action: 'OFF_MRP_SET',
        entityTable: 'settings',
        entityId: actor.firmId,
        summary: '${bp / 100}% off the printed price on every medicine',
        before: {'off_mrp_bp': was},
        after: {'off_mrp_bp': '$bp'},
      );
    });
  }

  /// Runs [body] with a writer whose every return goes into one
  /// transaction, after checking that each batch of [fromLots] still holds
  /// what is to go back out of it.
  ///
  /// An expiry return to one supplier is a return against each delivery its
  /// batches came in on; written together, a refusal on the third leaves
  /// nothing of the first two.
  Future<T> returnsTogether<T>(
    ActorContext actor,
    Map<String, Qty> fromLots,
    Future<T> Function(PurchaseReturnWriter sameTransaction) body,
  ) => _runner.run(actor, (tx) async {
    for (final MapEntry(key: lotId, value: qty) in fromLots.entries) {
      final row = await tx.selectOne(
        'SELECT l.lot_no, COALESCE(SUM(s.qty_delta_thousandths), 0) AS qty '
        'FROM stock_lots l LEFT JOIN stock_ledger s '
        '  ON s.lot_id = l.id AND s.deleted_at_utc IS NULL '
        "  AND s.location_code = 'MAIN' "
        'WHERE l.id = ? AND l.firm_id = ? GROUP BY l.id',
        [lotId, actor.firmId],
      );
      if (row == null || row.read<int>('qty') < qty.inThousandths) {
        throw ReturnRefused(
          'Batch ${row?.read<String>('lot_no') ?? lotId} no longer holds '
          '${qty.display} on the shop floor: some of it has been sold or '
          'sent back since the list was read.',
        );
      }
    }
    return body(_SameTransaction(purchaseReturnContextOn(tx)));
  });
}

/// A [PurchaseReturnWriter] on a transaction already open: each "new"
/// transaction is that one.
final class _SameTransaction implements PurchaseReturnWriter {
  _SameTransaction(this._context);

  final PurchaseReturnWriteContext _context;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(PurchaseReturnWriteContext write) body,
  ) => body(_context);
}

/// Writes the Schedule register's rows for a bill as it posts: one per line
/// of a Schedule medicine, against the prescription the bill carries.
///
/// Inside the sale's own transaction, after its lines are written, so a
/// register row cannot exist for a bill that did not post, nor a Schedule
/// line without one: the use case has already refused a bill without a
/// complete prescription, and the table refuses blank names besides.
Future<void> keepScheduleRegister(
  Tx tx, {
  required String documentId,
  required Map<int, String> lineIdByNo,
  required List<DocumentLinePosting> lines,
  required Prescription? prescription,
}) async {
  final itemIds = {for (final l in lines) ?l.itemId}.toList();
  if (itemIds.isEmpty) return;
  final rows = await tx.select(
    'SELECT id, schedule_class FROM items '
    'WHERE firm_id = ? AND schedule_class IS NOT NULL '
    'AND id IN (${List.filled(itemIds.length, '?').join(', ')})',
    [tx.actor.firmId, ...itemIds],
  );
  final scheduled = {
    for (final r in rows)
      r.read<String>('id'): r.read<String>('schedule_class'),
  };
  if (scheduled.isEmpty) return;
  final rx = prescription;
  if (rx == null || rx.gaps.isNotEmpty) {
    // The use case refuses this first, in words. Reaching here means a
    // writer was called without it, and the register is not optional.
    throw PrescriptionRefused(
      medicines: [
        for (final l in lines)
          if (scheduled.containsKey(l.itemId)) l.itemNameSnapshot,
      ],
      missing: rx?.gaps ?? const ['prescription'],
    );
  }
  for (final line in lines) {
    final schedule = scheduled[line.itemId];
    final lineId = lineIdByNo[line.lineNo];
    if (schedule == null || lineId == null) continue;
    await tx.insert('prescriptions', {
      'document_id': documentId,
      'document_line_id': lineId,
      'item_id': line.itemId,
      'schedule_class': schedule,
      'patient_name': rx.patientName.trim(),
      'patient_address': _blank(rx.patientAddress),
      'prescriber_name': rx.prescriberName.trim(),
      'prescriber_reg_no': rx.prescriberRegNo.trim(),
      'prescription_ref': _blank(rx.reference),
    });
  }
}

String? _blank(String? text) {
  final t = text?.trim() ?? '';
  return t.isEmpty ? null : t;
}
