import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';

/// The one and only way anything is written to this database.
///
/// Every mutation in the application goes through [TxRunner.run]. There is no
/// second path, and `no_db_write_outside_uow` in `pk_lints` makes a direct
/// write a build failure rather than a review comment.
///
/// This is what makes the previous build's central defect structurally
/// impossible. That app's checkout did this:
///
/// ```dart
/// void _finishSale(BuildContext context, dynamic cartNotifier, String msg) {
///   ScaffoldMessenger.of(context).showSnackBar(
///     SnackBar(content: Text('Sale processed via $msg! Thermal receipt printed.')));
///   cartNotifier.clearCart();
/// }
/// ```
///
/// It announced a sale, cleared the cart, and wrote nothing. `grep
/// InvoicesCompanion.insert lib/` returned zero hits across the whole
/// repository. Here, a use case that does not write cannot report success:
/// [run] returns only after a commit that has already been checked.
///
/// Every run, in order:
///
///  1. opens a transaction;
///  2. hands the body a [Tx] that stamps the envelope on every row;
///  3. appends a `change_log` entry for every mutation, so nothing can be
///     created that the M13 sync will not know about;
///  4. writes the buffered `audit_log` rows;
///  5. asserts every journal entry the body touched balances to the paisa;
///  6. commits.
///
/// If any step throws, the transaction rolls back whole. There is no partial
/// sale.
final class TxRunner {
  TxRunner({
    required this.database,
    required this.ids,
    required this.hlc,
  });

  final AppDatabase database;
  final IdGenerator ids;
  final HlcClock hlc;

  /// Runs [body] as a single atomic unit.
  Future<T> run<T>(
    ActorContext actor,
    Future<T> Function(Tx tx) body,
  ) async {
    return database.transaction(() async {
      final tx = Tx._(database, actor, ids, hlc);
      await tx._begin();
      final result = await body(tx);
      await tx._finish();
      return result;
    });
  }
}

/// The handle a use case writes through.
///
/// It is not a general-purpose database connection. It can insert, update and
/// soft-delete rows, and it can read; it cannot hard-delete anything, because
/// this product never destroys a record — a deletion is a void plus a
/// reversing entry, and the row stays visible as a tombstone.
final class Tx {
  // Positional, so the fields can stay private. A use case must not be able
  // to reach the database through the handle it writes with — that would be a
  // second write path, which is the one thing this class exists to prevent.
  Tx._(this._db, this.actor, this._ids, this._hlc);

  final AppDatabase _db;
  final IdGenerator _ids;
  final HlcClock _hlc;

  /// Who is writing, from where, and at what instant. Required, never
  /// inferred, and shared by every row this transaction produces.
  final ActorContext actor;

  final List<_PendingAudit> _audits = [];
  final Set<String> _touchedJournalEntries = {};

  int _seq = 0;
  int _mutations = 0;

  /// How many rows this transaction has written so far. Used by tests and by
  /// the fault-injection harness.
  int get mutationCount => _mutations;

  Future<void> _begin() async {
    final row = await _db
        .customSelect(
          'SELECT change_seq FROM devices WHERE id = ?',
          variables: [Variable<String>(actor.deviceId)],
        )
        .getSingleOrNull();
    if (row == null) {
      throw StateError(
        'Device ${actor.deviceId} is not registered in this database. '
        'A write cannot be attributed to a device that does not exist.',
      );
    }
    _seq = row.read<int>('change_seq');
  }

  Future<void> _finish() async {
    for (final audit in _audits) {
      await _writeAudit(audit);
    }
    await _db.customStatement(
      'UPDATE devices SET change_seq = ? WHERE id = ?',
      [_seq, actor.deviceId],
    );
    await assertBooksBalance();
  }

  // ---------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------

  /// Runs a read inside this transaction, so a use case sees its own writes.
  Future<List<QueryRow>> select(String sql, [List<Object?> args = const []]) =>
      _db.customSelect(sql, variables: _bind(args)).get();

  Future<QueryRow?> selectOne(String sql,
          [List<Object?> args = const []]) =>
      _db.customSelect(sql, variables: _bind(args)).getSingleOrNull();

  // ---------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------

  /// Inserts a row into [table], stamping the universal envelope, and returns
  /// its id.
  ///
  /// [values] carries only the business columns. Supplying an envelope column
  /// by hand is rejected: the envelope is not something a caller gets to have
  /// an opinion about, and a use case that could set its own `created_by`
  /// could forge an audit trail.
  Future<String> insert(
    String table,
    Map<String, Object?> values, {
    String? id,
  }) async {
    _rejectEnvelopeColumns(table, values);

    final rowId = id ?? _ids.next();
    final hlc = _hlc.next().value;
    final row = <String, Object?>{
      'id': rowId,
      'firm_id': actor.firmId,
      'created_at_utc': actor.epochMillis,
      'updated_at_utc': actor.epochMillis,
      'created_by': actor.userId,
      'updated_by': actor.userId,
      'deleted_at_utc': null,
      'origin_device_id': actor.deviceId,
      'hlc': hlc,
      'rev': 1,
      ...values,
    };

    final columns = row.keys.toList();
    final placeholders = List.filled(columns.length, '?').join(', ');
    await _db.customStatement(
      'INSERT INTO $table (${columns.join(', ')}) VALUES ($placeholders)',
      _checked([for (final c in columns) row[c]]),
    );

    _mutations++;
    _noteJournalTouch(table, rowId, row);
    await _recordChange(
      table: table,
      entityId: rowId,
      op: 'insert',
      payload: row,
      hlc: hlc,
      rev: 1,
    );
    return rowId;
  }

  /// Updates the business columns of one row, bumping its revision and
  /// stamping a fresh HLC.
  ///
  /// The revision bump is not decoration. It is how a LAN merge in M13 tells a
  /// stale copy from a current one, and how the conflict inbox shows a
  /// shopkeeper what actually changed rather than silently overwriting.
  Future<void> update(
    String table,
    String id,
    Map<String, Object?> values,
  ) async {
    if (values.isEmpty) {
      throw ArgumentError.value(values, 'values', 'must not be empty');
    }
    _refuseAppendOnly(table, 'rewritten');
    _rejectEnvelopeColumns(table, values);

    final hlc = _hlc.next().value;
    final assignments = <String>[
      for (final c in values.keys) '$c = ?',
      'updated_at_utc = ?',
      'updated_by = ?',
      'hlc = ?',
      'rev = rev + 1',
    ];
    final args = <Object?>[
      ...values.values,
      actor.epochMillis,
      actor.userId,
      hlc,
      id,
      actor.firmId,
    ];

    // The firm predicate is not optional. A DAO bug that lost it would let a
    // multi-firm user's write land on another firm's row, and nothing else in
    // the stack would notice.
    // Tombstoned rows are read-only. Without the predicate, `archiveItem` on
    // an already-archived item reported success, bumped the revision and
    // broadcast an update for a row every other counter has deleted.
    await _db.customStatement(
      'UPDATE $table SET ${assignments.join(', ')} '
      'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
      _checked(args),
    );

    final after = await selectOne(
      'SELECT * FROM $table WHERE id = ? AND firm_id = ? '
      'AND deleted_at_utc IS NULL',
      [id, actor.firmId],
    );
    if (after == null) {
      throw StateError(
        'Update of $table.$id affected no row in firm ${actor.firmId}: it '
        'does not exist, or it has been deleted.',
      );
    }

    _mutations++;
    _noteJournalTouch(table, id, after.data);
    await _recordChange(
      table: table,
      entityId: id,
      op: 'update',
      payload: {'id': id, ...values},
      hlc: hlc,
      rev: after.read<int>('rev'),
    );
  }

  /// Ledgers that may only ever be appended to.
  ///
  /// Everything whose rows are evidence: the stock ledger and the double-entry
  /// journal because a balance is derived by summing them in order, and the
  /// audit and outbox logs because their whole purpose is that nothing can be
  /// taken out of them.
  static const _appendOnly = {
    'stock_ledger',
    'journal_entries',
    'journal_lines',
    'audit_log',
    'change_log',
  };

  /// Refuses to change a row in a ledger that may only be appended to.
  ///
  /// A financial ledger is corrected by a reversing row, never by editing or
  /// hiding one. `stock_ledger.balance_after_thousandths` is a running total
  /// stamped at the moment its row was written, so a row changed or removed
  /// underneath it can never be recomputed — and worse, `rebuildStockBalances`
  /// will happily "repair" the cache to match the tampered quantity, making it
  /// permanent and self-consistent.
  ///
  /// The update path is the more dangerous of the two, and had no guard at
  /// all. Rewriting `journal_lines.account_id` moves money to a different
  /// account while `assertBooksBalance` still passes, because the debits and
  /// the credits are untouched: the books balance and they are wrong.
  void _refuseAppendOnly(String table, String what) {
    if (!_appendOnly.contains(table)) return;
    throw StateError(
      '$table is append-only and cannot be $what: correct it with a '
      'reversing entry.',
    );
  }

  /// Marks a row deleted without destroying it.
  ///
  /// Six-year retention under s.24 STA and s.174(3) ITO is a legal obligation,
  /// not a preference, and a shopkeeper who deletes a bill by accident on a
  /// Tuesday will want it back on the Wednesday.
  Future<void> softDelete(String table, String id) async {
    _refuseAppendOnly(table, 'struck out');
    // Read first. Deleting a journal line unbalances its entry, and
    // `assertBooksBalance` only inspects entries this transaction touched —
    // so a delete that does not register the touch escapes the pre-commit
    // check entirely and leaves the books wrong until the reconciler runs,
    // possibly months later.
    final before = await selectOne(
      'SELECT * FROM $table WHERE id = ? AND firm_id = ?',
      [id, actor.firmId],
    );
    if (before == null) {
      throw StateError('No row $table.$id in firm ${actor.firmId} to delete.');
    }
    if (before.data['deleted_at_utc'] != null) {
      // Otherwise the UPDATE matches nothing, the mutation counter still
      // rises, and a delete that did not happen is broadcast to every other
      // counter through the outbox.
      throw StateError('Row $table.$id in firm ${actor.firmId} is already '
          'deleted.');
    }
    _noteJournalTouch(table, id, before.data);

    final hlc = _hlc.next().value;
    await _db.customStatement(
      'UPDATE $table SET deleted_at_utc = ?, updated_at_utc = ?, '
      'updated_by = ?, hlc = ?, rev = rev + 1 '
      'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
      _checked([
        actor.epochMillis,
        actor.epochMillis,
        actor.userId,
        hlc,
        id,
        actor.firmId,
      ]),
    );

    final after = await selectOne(
      'SELECT rev FROM $table WHERE id = ? AND firm_id = ?',
      [id, actor.firmId],
    );
    if (after == null) {
      throw StateError('No row $table.$id in firm ${actor.firmId} to delete.');
    }

    _mutations++;
    await _recordChange(
      table: table,
      entityId: id,
      op: 'delete',
      payload: {'id': id, 'deleted_at_utc': actor.epochMillis},
      hlc: hlc,
      rev: after.read<int>('rev'),
    );
  }

  /// Records what a human did, in words, for the activity dashboard and the
  /// audit trail.
  ///
  /// Buffered and written just before commit, so an audit row can never
  /// survive an action that rolled back — and a successful action can never
  /// finish without one.
  void audit({
    required String action,
    required String entityTable,
    required String entityId,
    String? summary,
    int? amountPaisa,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
  }) {
    _audits.add(
      _PendingAudit(
        action: action,
        entityTable: entityTable,
        entityId: entityId,
        summary: summary,
        amountPaisa: amountPaisa,
        before: before,
        after: after,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Pre-commit checks
  // ---------------------------------------------------------------------

  /// Asserts that every journal entry this transaction touched balances.
  ///
  /// Scoped to what changed rather than the whole ledger, because a shop with
  /// three years of history cannot afford a full-table sum on every sale. The
  /// whole-database version lives on [AppDatabase] and runs in the reconciler,
  /// the data-health check, and after every integration test in the suite.
  ///
  /// The previous build had a balance check too. Its tolerance was `> 0.01`,
  /// which existed solely to hide the drift its REAL columns accumulated. A
  /// ledger that only balances to within a paisa is not a ledger, so the
  /// comparison here is integer equality and nothing else.
  Future<void> assertBooksBalance() async {
    if (_touchedJournalEntries.isEmpty) return;

    final ids = _touchedJournalEntries.toList();
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await select(
      '''
      SELECT je.id            AS entry_id,
             je.entry_no      AS entry_no,
             je.total_debit_paisa  AS declared_debit,
             je.total_credit_paisa AS declared_credit,
             COALESCE(SUM(jl.debit_paisa), 0)  AS actual_debit,
             COALESCE(SUM(jl.credit_paisa), 0) AS actual_credit
      FROM journal_entries je
      LEFT JOIN journal_lines jl
        ON jl.journal_entry_id = je.id AND jl.deleted_at_utc IS NULL
      WHERE je.id IN ($placeholders)
      GROUP BY je.id
      ''',
      ids,
    );

    for (final row in rows) {
      final declaredDebit = row.read<int>('declared_debit');
      final declaredCredit = row.read<int>('declared_credit');
      final actualDebit = row.read<int>('actual_debit');
      final actualCredit = row.read<int>('actual_credit');
      final entryNo = row.read<String>('entry_no');

      if (actualDebit != actualCredit) {
        throw BooksDoNotBalance(
          entryNo: entryNo,
          debitPaisa: actualDebit,
          creditPaisa: actualCredit,
          detail: 'lines do not balance against each other',
        );
      }
      if (actualDebit != declaredDebit || actualCredit != declaredCredit) {
        throw BooksDoNotBalance(
          entryNo: entryNo,
          debitPaisa: actualDebit,
          creditPaisa: actualCredit,
          detail: 'lines total $actualDebit but the entry declares '
              '$declaredDebit debit and $declaredCredit credit',
        );
      }
    }
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  void _noteJournalTouch(
    String table,
    String id,
    Map<String, Object?> row,
  ) {
    if (table == 'journal_entries') {
      _touchedJournalEntries.add(id);
    } else if (table == 'journal_lines') {
      final entry = row['journal_entry_id'];
      if (entry is String) _touchedJournalEntries.add(entry);
    }
  }

  Future<void> _recordChange({
    required String table,
    required String entityId,
    required String op,
    required Map<String, Object?> payload,
    required String hlc,
    required int rev,
  }) async {
    _seq++;
    await _db.customStatement(
      '''
      INSERT INTO change_log (
        id, firm_id, created_at_utc, updated_at_utc, created_by, updated_by,
        deleted_at_utc, origin_device_id, hlc, rev,
        seq, entity_table, entity_id, op, payload_json, entity_hlc,
        entity_rev, at_utc, sync_state
      ) VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?,
        'pending')
      ''',
      [
        _ids.next(),
        actor.firmId,
        actor.epochMillis,
        actor.epochMillis,
        actor.userId,
        actor.userId,
        actor.deviceId,
        hlc,
        _seq,
        table,
        entityId,
        op,
        jsonEncode(payload),
        hlc,
        rev,
        actor.epochMillis,
      ],
    );
  }

  Future<void> _writeAudit(_PendingAudit audit) async {
    await _db.customStatement(
      '''
      INSERT INTO audit_log (
        id, firm_id, created_at_utc, updated_at_utc, created_by, updated_by,
        deleted_at_utc, origin_device_id, hlc, rev,
        action_code, entity_table, entity_id, summary, before_json,
        after_json, amount_paisa, at_utc
      ) VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        _ids.next(),
        actor.firmId,
        actor.epochMillis,
        actor.epochMillis,
        actor.userId,
        actor.userId,
        actor.deviceId,
        _hlc.next().value,
        audit.action,
        audit.entityTable,
        audit.entityId,
        audit.summary,
        audit.before == null ? null : jsonEncode(audit.before),
        audit.after == null ? null : jsonEncode(audit.after),
        audit.amountPaisa,
        actor.epochMillis,
      ],
    );
  }

  /// The same refusal as [_bind], for the raw-value binding that
  /// `customStatement` uses.
  ///
  /// The read path has rejected a bound `double` since day one, and the write
  /// path — the one that actually stores money — did not. A REAL that happens
  /// to be integral is coerced silently into a STRICT INTEGER column, so the
  /// first sign of a float creeping into the money layer would have been a
  /// rounding difference in a report months later.
  static List<Object?> _checked(List<Object?> args) {
    for (final a in args) {
      if (a == null || a is int || a is String || a is bool) continue;
      throw ArgumentError.value(
        a,
        'args',
        'only int, String, bool and null may be written — a double here '
            'would be money represented as a float',
      );
    }
    return args;
  }

  static List<Variable<Object>> _bind(List<Object?> args) => [
        for (final a in args)
          if (a == null)
            const Variable<String>(null)
          else if (a is int)
            Variable<int>(a)
          else if (a is String)
            Variable<String>(a)
          else if (a is bool)
            Variable<int>(a ? 1 : 0)
          else
            throw ArgumentError.value(
              a,
              'args',
              'only int, String, bool and null may be bound — a double here '
                  'would be money represented as a float',
            ),
      ];

  static const Set<String> _envelopeColumns = {
    'id',
    'firm_id',
    'created_at_utc',
    'updated_at_utc',
    'created_by',
    'updated_by',
    'deleted_at_utc',
    'origin_device_id',
    'hlc',
    'rev',
  };

  void _rejectEnvelopeColumns(String table, Map<String, Object?> values) {
    for (final key in values.keys) {
      if (_envelopeColumns.contains(key)) {
        throw ArgumentError(
          'Cannot set envelope column "$key" on $table by hand. The envelope '
          'is stamped from the ActorContext so that it cannot be forged.',
        );
      }
    }
  }
}

/// Thrown before commit when a journal entry does not balance.
class BooksDoNotBalance implements Exception {
  const BooksDoNotBalance({
    required this.entryNo,
    required this.debitPaisa,
    required this.creditPaisa,
    required this.detail,
  });

  final String entryNo;
  final int debitPaisa;
  final int creditPaisa;
  final String detail;

  @override
  String toString() =>
      'Journal entry $entryNo does not balance: $detail '
      '(debit $debitPaisa paisa, credit $creditPaisa paisa). '
      'Nothing was saved.';
}

class _PendingAudit {
  const _PendingAudit({
    required this.action,
    required this.entityTable,
    required this.entityId,
    this.summary,
    this.amountPaisa,
    this.before,
    this.after,
  });

  final String action;
  final String entityTable;
  final String entityId;
  final String? summary;
  final int? amountPaisa;
  final Map<String, Object?>? before;
  final Map<String, Object?>? after;
}
