import 'dart:convert';

import 'package:pk_domain/pk_domain.dart';

import '../read/drift_app_queries.dart' show DriftAppQueries;
import '../read/drift_collection_queries.dart';
import 'drift_payment_writer.dart' show paymentContextOn;
import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// The drift implementation of [CollectionWriter] (M55).
///
/// One [TxRunner] transaction with the payment writer's own handle opened
/// on it, so a round's receipts are written by the code that writes every
/// receipt, its promises as M38 writes them, and the sheet itself as a row
/// in `settings` — all committing together or not at all.
///
/// The promise is written here rather than through `DriftUdhaarStore`
/// because that store opens a transaction of its own, and a transaction
/// opened inside another's body would be a second envelope on one commit.
/// The row is the same row: the same key, the same JSON, the same audit
/// action, so the khata, the chase list and the home screen read it as any
/// other promise.
final class DriftCollectionWriter implements CollectionWriter {
  const DriftCollectionWriter({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(CollectionWriteContext write) body,
  ) => runner.run(actor, (tx) => body(_Context(tx, sequences, runner.ids)));
}

final class _Context implements CollectionWriteContext {
  _Context(this._tx, this._sequences, this._ids)
    : payments = paymentContextOn(_tx, sequences: _sequences);

  final Tx _tx;
  final SequenceAllocator _sequences;
  final IdGenerator _ids;

  @override
  final PaymentWriteContext payments;

  @override
  ActorContext get actor => _tx.actor;

  @override
  Future<AllocatedNumber> nextNumber(String docType) async {
    final number = await _sequences.allocate(
      _tx,
      docType: docType,
      fiscalYear: actor.businessDate.fiscalYear,
    );
    return AllocatedNumber(
      formatted: number.formatted,
      series: number.series,
      sequence: number.sequence,
    );
  }

  @override
  Future<String> actorName() async {
    final row = await _tx.selectOne('SELECT name FROM users WHERE id = ?', [
      actor.userId,
    ]);
    return row?.read<String>('name') ?? '';
  }

  @override
  Future<SheetParty?> party(String partyId) async {
    // The khata's own figure, read inside this transaction with the one
    // expression every screen reads a balance from.
    final row = await _tx.selectOne(
      '${DriftAppQueries.partySelectSql} WHERE p.id = ? AND p.firm_id = ?',
      [partyId, actor.firmId],
    );
    if (row == null) return null;
    final party = DriftAppQueries.partyFromRow(row);
    return SheetParty(
      id: party.id,
      name: party.name,
      phone: party.phone,
      group: party.group,
      balance: party.balance,
    );
  }

  @override
  Future<int> unpricedLines(String partyId) async {
    final row = await _tx.selectOne(
      'SELECT COUNT(*) AS n FROM documents d '
      'JOIN document_lines dl ON dl.document_id = d.id '
      'WHERE d.firm_id = ? AND d.party_id = ? '
      '  AND $unbilledChallanSql AND $unpricedLineSql',
      [actor.firmId, partyId],
    );
    return row?.read<int>('n') ?? 0;
  }

  @override
  Future<CollectionSheet?> sheet(String sheetId) async {
    final row = await _tx.selectOne(
      'SELECT setting_value FROM settings '
      'WHERE id = ? AND firm_id = ? AND setting_key = ? '
      '  AND deleted_at_utc IS NULL',
      [sheetId, actor.firmId, collectionSheetKey(sheetId)],
    );
    if (row == null) return null;
    return CollectionSheet.fromJson(
      sheetId,
      jsonDecode(row.read<String>('setting_value')),
    );
  }

  @override
  Future<String> addSheet(CollectionSheet sheet) async {
    // The row's id is the sheet's, and is in its key, so no two sheets can
    // share a key however many are made in a day on however many counters.
    final id = _ids.next();
    await _tx.insert('settings', {
      'setting_key': collectionSheetKey(id),
      'setting_value': jsonEncode(sheet.toJson()),
      'value_type': 'json',
    }, id: id);
    _tx.audit(
      action: 'COLLECTION_SHEET_MADE',
      entityTable: 'settings',
      entityId: id,
      summary:
          '${sheet.sheetNo} for ${sheet.collector}: '
          '${sheet.lines.length} customer(s), '
          '${sheet.expected.amountOnly} to collect',
      amountPaisa: sheet.expected.inPaisa,
      after: {'sheet_no': sheet.sheetNo, 'collector': sheet.collector},
    );
    return id;
  }

  @override
  Future<void> putSheet(
    CollectionSheet sheet, {
    required String action,
    required String summary,
    Money? amount,
  }) async {
    await _tx.update('settings', sheet.id, {
      'setting_value': jsonEncode(sheet.toJson()),
    });
    _tx.audit(
      action: action,
      entityTable: 'settings',
      entityId: sheet.id,
      summary: summary,
      amountPaisa: amount?.inPaisa,
      after: {'sheet_no': sheet.sheetNo},
    );
  }

  @override
  Future<String> addPromise(
    PromiseDraft draft, {
    required String partyName,
  }) async {
    final today = actor.businessDate.value;
    if (draft.problemOn(today) case final problem?) {
      throw CollectionRefused(problem);
    }
    // As DriftUdhaarStore.recordPromise writes it: the row's id is the
    // promise's, and is in its key.
    final id = _ids.next();
    await _tx.insert('settings', {
      'setting_key': promiseKey(draft.partyId, id),
      'setting_value': jsonEncode(draft.toJson(madeOn: today)),
      'value_type': 'json',
    }, id: id);
    final amount = draft.amount;
    _tx.audit(
      action: 'PROMISE_RECORDED',
      entityTable: 'parties',
      entityId: draft.partyId,
      summary:
          '$partyName promised to pay '
          '${amount == null ? '' : '${amount.amountOnly} '}'
          'by ${draft.promisedFor}',
      amountPaisa: amount?.inPaisa,
      after: {'promise_id': id, 'for': draft.promisedFor},
    );
    return id;
  }
}
