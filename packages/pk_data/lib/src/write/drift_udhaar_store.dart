import 'dart:convert';

import 'package:pk_domain/pk_domain.dart';

import 'tx_runner.dart';

/// The drift implementation of [UdhaarStore] (M38).
///
/// A promise is a row in the shop's `settings`, one per promise, written
/// through [TxRunner] like everything else: so it is audited, it reaches
/// the sync outbox and the other counters (M13), and it rolls back whole if
/// anything after it fails. No table was added for it — the schema version
/// was not this milestone's to take — and none was needed: a promise is a
/// small, rarely-changing fact about a customer, which is what `settings`
/// already holds for printers and counters, and its JSON value carries the
/// four things a promise is.
final class DriftUdhaarStore implements UdhaarStore {
  DriftUdhaarStore(this._runner, this._ids);

  /// Asked for each time rather than held; see `DriftPrinterSettings`.
  final TxRunner Function() _runner;
  final IdGenerator _ids;

  @override
  Future<String> recordPromise(ActorContext actor, PromiseDraft draft) =>
      _runner().run(actor, (tx) async {
        final today = actor.businessDate.value;
        final problem = draft.problemOn(today);
        if (problem != null) throw UdhaarRefused(problem);
        final party = await tx.selectOne(
          'SELECT name FROM parties '
          'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
          [draft.partyId, actor.firmId],
        );
        if (party == null) {
          throw const UdhaarRefused('That customer is not in this khata.');
        }
        // The row's id is the promise's, and is in its key, so the key is
        // unique however many promises one customer makes in a day.
        final id = _ids.next();
        await tx.insert('settings', {
          'setting_key': promiseKey(draft.partyId, id),
          'setting_value': jsonEncode(draft.toJson(madeOn: today)),
          'value_type': 'json',
        }, id: id);
        final amount = draft.amount;
        tx.audit(
          action: 'PROMISE_RECORDED',
          entityTable: 'parties',
          entityId: draft.partyId,
          summary:
              '${party.read<String>('name')} promised to pay '
              '${amount == null ? '' : '${amount.amountOnly} '}'
              'by ${draft.promisedFor}',
          amountPaisa: amount?.inPaisa,
          after: {'promise_id': id, 'for': draft.promisedFor},
        );
        return id;
      });

  @override
  Future<void> withdrawPromise(ActorContext actor, String promiseId) =>
      _runner().run(actor, (tx) async {
        final row = await tx.selectOne(
          'SELECT setting_key, setting_value FROM settings '
          'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
          [promiseId, actor.firmId],
        );
        final key = row?.read<String>('setting_key') ?? '';
        if (row == null || !key.startsWith(promiseKeyPrefix)) {
          throw const UdhaarRefused('There is no such promise to take off.');
        }
        final json = jsonDecode(row.read<String>('setting_value'));
        if (json is! Map<String, Object?>) {
          throw const UdhaarRefused('That promise cannot be read.');
        }
        if (json['withdrawn_on'] != null) {
          throw const UdhaarRefused('That promise was already taken off.');
        }
        // Marked, never deleted: a promise taken off is still part of what
        // the shop knows about this customer.
        await tx.update('settings', promiseId, {
          'setting_value': jsonEncode({
            ...json,
            'withdrawn_on': actor.businessDate.value,
          }),
        });
        tx.audit(
          action: 'PROMISE_WITHDRAWN',
          entityTable: 'parties',
          entityId: json['party_id'] as String? ?? '',
          summary: 'Promise to pay by ${json['for']} taken off',
          after: {'promise_id': promiseId},
        );
      });
}
