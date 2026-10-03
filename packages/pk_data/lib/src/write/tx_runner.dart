import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';

/// The one and only way anything is written to this database.
///
/// Every mutation in the application goes through [TxRunner.run]. There is no
/// second path, and the `one_write_path` rule in `tool/arch_check.dart` makes a
/// direct write a build failure rather than a review comment.
///
/// This comment used to credit a lint package that did not exist. It was two
/// empty directories, and the melos step claiming to run it matched no package
/// and exited zero. So for several weeks the file documenting this project's
/// central guarantee named an enforcement mechanism that was not running. The
/// rule named above is real, is self-tested, and fails the build if it ever
/// stops being able to fire — and `no_phantom_gate` now refuses the old name
/// anywhere in the tree, so nobody can cite it again by accident.
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
///  4. refuses anything dated inside books the owner has closed, and
///     anything Data Lock guards, unless somebody's PIN stands behind it
///     (M42);
///  5. writes the buffered `audit_log` rows;
///  6. asserts every journal entry the body touched balances to the paisa;
///  7. commits.
///
/// If any step throws, the transaction rolls back whole. There is no partial
/// sale.
///
/// ## The locks (M42)
///
/// This is the one place every write passes, so it is where the owner's
/// locks are kept, the way M9's roles are kept at the service every screen
/// goes through. A lock on a screen protects only that screen; a bill
/// back-dated by an import, a counter on an older build, or a cancel from a
/// page nobody thought to guard all come through here.
///
/// When a lock refuses, the transaction rolls back with [ApprovalNeeded].
/// If an [approver] is wired -- the app wires one that shows a PIN prompt --
/// the runner asks it, outside the transaction, and runs the body again
/// with the approval it was given. Asking outside is deliberate: a prompt
/// shown while the transaction is open would hold the books shut for as
/// long as somebody takes to find their glasses, and a counter syncing in
/// the meantime would wait on it. The cost is that the body may run twice,
/// which it already has to survive: everything it wrote the first time was
/// rolled back, and it reads the books afresh.
final class TxRunner {
  TxRunner({
    required this.database,
    required this.ids,
    required this.hlc,
    this.approver,
  });

  final AppDatabase database;
  final IdGenerator ids;
  final HlcClock hlc;

  /// Who is asked for a PIN when a lock refuses (M42). Null in a test or a
  /// tool, where the refusal in words is the answer.
  final Approver? approver;

  /// Marks a zone as already inside [run], so a run nested in another's
  /// body throws its refusal out to the outermost one instead of asking for
  /// a PIN with the outer transaction still open.
  static final Object _inside = Object();

  /// Runs [body] as a single atomic unit.
  Future<T> run<T>(ActorContext actor, Future<T> Function(Tx tx) body) async {
    final outermost = Zone.current[_inside] == null;
    final approvals = <Approval>[];
    while (true) {
      try {
        return await runZoned(
          () => database.transaction(() async {
            final tx = Tx._(
              database,
              actor,
              ids,
              hlc,
              List.unmodifiable(approvals),
            );
            await tx._begin();
            // M68: the body runs knowing its Tx, for a gate wrapped round a
            // writer that is only handed the writer's own handle (Tx.current).
            final result = await runZoned(
              () => body(tx),
              zoneValues: {Tx._current: tx},
            );
            await tx._finish();
            return result;
          }),
          zoneValues: {_inside: true},
        );
      } on ApprovalNeeded catch (needed) {
        final ask = approver;
        if (!outermost || ask == null) rethrow;
        // Once per kind. An approval that did not satisfy the check it was
        // given for is a bug, and asking again would ask for ever.
        if (approvals.any((a) => a.kind == needed.kind)) rethrow;
        final given = await ask(needed);
        if (given == null) rethrow;
        approvals.add(given);
      }
    }
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
  Tx._(this._db, this.actor, this._ids, this._hlc, this._approvals);

  final AppDatabase _db;
  final IdGenerator _ids;
  final HlcClock _hlc;

  /// The PINs given for this run, each already checked (M42).
  final List<Approval> _approvals;

  /// Who is writing, from where, and at what instant. Required, never
  /// inferred, and shared by every row this transaction produces.
  final ActorContext actor;

  final List<_PendingAudit> _audits = [];
  final Set<String> _touchedJournalEntries = {};

  int _seq = 0;
  int _mutations = 0;

  /// The owner's locks as this transaction found them (M42).
  BookLocks? _locks;

  /// Rows this transaction writes or strikes out inside closed books.
  final List<({String table, String id, String date, String what})>
  _inClosedBooks = [];

  /// Each master row's fields as they were before this transaction and as
  /// they are now, keyed `table/id` (M42).
  final Map<String, ({Map<String, Object?> before, Map<String, Object?> after})>
  _diffs = {};

  /// How many rows this transaction has written so far. Used by tests and by
  /// the fault-injection harness.
  int get mutationCount => _mutations;

  // M68 -------------------------------------------------------------------

  static final Object _current = Object();

  /// The transaction the caller is running inside, or null outside every
  /// run (M68).
  ///
  /// For a check made beneath a run by code that is never handed its Tx: a
  /// gate wrapped round the sale writer, which sees only the writer's own
  /// handle, but must ask for the owner's PIN and leave its audit row in
  /// the bill's own commit. Not a second way to write: it is only ever the
  /// run the caller is already inside, with everything that run checks at
  /// commit.
  static Tx? get current => Zone.current[_current] as Tx?;

  /// The PIN given on this run for [needed]'s kind (M68).
  ///
  /// Throws [needed] when none was: the run rolls back whole and, at the
  /// outermost run, the approver is asked and the body run again with the
  /// answer -- the same round M42's locks make. Whoever asks for it leaves
  /// the audit row that names the approval, inside this transaction.
  Approval approvedFor(ApprovalNeeded needed) {
    final given = _approval(needed.kind);
    if (given == null) throw needed;
    return given;
  }

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
    _checkClosedBooks();
    await _checkDataLock();
    _mergeDiffs();
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

  Future<QueryRow?> selectOne(String sql, [List<Object?> args = const []]) =>
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

    await _guardRow(table, rowId, row);

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
    await _guardUpdate(table, id, values);
    final was = await _fieldsBefore(table, id, values);

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
    if (was != null) _noteDiff(table, id, was, values);
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
      throw StateError(
        'Row $table.$id in firm ${actor.firmId} is already '
        'deleted.',
      );
    }
    _noteJournalTouch(table, id, before.data);
    await _guardRow(table, id, before.data, undoing: true);

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
  // The owner's locks (M42)
  // ---------------------------------------------------------------------

  /// The owner's locks as this transaction found them.
  ///
  /// Read once, on first use, inside the transaction, and kept. Kept so a
  /// transaction that changes a lock is judged by the lock it found: turning
  /// Data Lock off is itself guarded by Data Lock, which only works if the
  /// check at commit still sees it on. Read inside the transaction so a lock
  /// that has just arrived from the master by sync binds this counter's very
  /// next write.
  Future<BookLocks> bookLocks() async {
    final held = _locks;
    if (held != null) return held;
    final rows = await select(
      'SELECT setting_key, setting_value FROM settings '
      'WHERE firm_id = ? AND setting_key IN (?, ?, ?) '
      'AND deleted_at_utc IS NULL',
      [
        actor.firmId,
        booksClosedThroughSetting,
        dataLockSetting,
        autoLockSetting,
      ],
    );
    String? value(String key) => rows
        .where((r) => r.read<String>('setting_key') == key)
        .map((r) => r.read<String>('setting_value'))
        .firstOrNull;
    final through = value(booksClosedThroughSetting);
    return _locks = BookLocks(
      // M68: days that lock themselves move the date on by themselves,
      // worked out here on every write, so a phone left open past midnight
      // is closed at midnight whether or not the kept date has moved yet.
      closedThrough: laterClosing(
        through == null ? null : BusinessDate.tryParse(through),
        await _autoClosedThrough(value(autoLockSetting)),
      ),
      dataLock: value(dataLockSetting) == '1',
    );
  }

  /// M68: the last day the owner's rule for days that lock themselves has
  /// closed, as of today.
  Future<BusinessDate?> _autoClosedThrough(String? rule) async {
    final lock = AutoLock.fromJson(rule);
    if (!lock.isOn) return null;
    BusinessDate? counted;
    if (lock.mode == AutoLockMode.atDayClose) {
      final row = await selectOne(
        'SELECT MAX(at_utc) AS at FROM audit_log '
        "WHERE firm_id = ? AND action_code = 'DAY_CLOSED'",
        [actor.firmId],
      );
      final at = row?.readNullable<int>('at');
      counted = at == null
          ? null
          : BusinessDate.fromUtc(
              DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
            );
    }
    // Today by the device's own clock, not the entry's date: a bill dated
    // back to the 1st is judged by what is closed today, not on the 1st.
    return lock.closedThroughOn(
      BusinessDate.now(_hlc.clock),
      lastDayClosed: counted,
    );
  }

  /// The date each kind of row carries, which is the date the books file it
  /// under. Everything that reaches the books writes at least one of these:
  /// a sale its bill, its journal entry and its stock; a receipt its payment
  /// and its entry; a correction its reversal.
  static const _dateOf = {
    'documents': 'doc_date_local',
    'journal_entries': 'entry_date_local',
    'payments': 'payment_date_local',
    'stock_ledger': 'occurred_on_local',
    // M50: a qist plan is filed under its bill's day, and a warranty claim
    // under the day it was written down.
    'qist_plans': 'sold_on_local',
    'warranty_claims': 'claimed_on_local',
    // M65: a day of the staff register under its day, and a month's wages
    // under the day they were handed over.
    'attendance': 'day_local',
    'salary_slips': 'paid_on_local',
  };

  /// Rows whose every change is a change to what their day says (M65). A
  /// register mark has no status and never moves day; changing Monday's
  /// "absent" to "present" is still changing Monday, which the owner closed.
  static const _guardedWhole = {'attendance'};

  /// Papers that are not in the books at all. A quotation dated last month
  /// changes no figure anybody was given.
  static const _offTheBooks = {
    'quotation',
    'proforma',
    'sale_order',
    'purchase_order',
  };

  /// Refuses a row about to be written or struck out inside closed books.
  ///
  /// A row written is judged by its own date. A row struck out is judged by
  /// the date it already carries, because striking it out changes what that
  /// day's books say.
  Future<void> _guardRow(
    String table,
    String id,
    Map<String, Object?> row, {
    bool undoing = false,
  }) async {
    final column = _dateOf[table];
    if (column == null) return;
    final date = row[column];
    if (date is! String) return;
    if (table == 'documents') {
      if (_offTheBooks.contains(row['doc_type'])) return;
      // A draft is not in the books until it is posted, which is an update
      // and is judged there.
      final status = row['status'];
      if (!undoing && (status == null || status == 'draft')) return;
    }
    await _guardDate(table, id, date, _describe(table, row, undoing: undoing));
  }

  /// Refuses an update that would change what a closed day's books say.
  ///
  /// Two kinds of update do: a status that takes a row out of the books
  /// (`void`) or puts a draft into them (`posted`), and a change of date. A
  /// payment's cheque clearing or bouncing is neither -- the bank's news is
  /// dated the day it comes, and is posted then -- and nor is a later
  /// receipt settling an old bill, which moves only its balance. Those are
  /// today's events touching an old row, and they go through.
  Future<void> _guardUpdate(
    String table,
    String id,
    Map<String, Object?> values,
  ) async {
    final column = _dateOf[table];
    if (column == null) return;
    if (_guardedWhole.contains(table)) {
      // M65: judged by the day it already carries.
      final was = await selectOne(
        'SELECT * FROM $table WHERE id = ? AND firm_id = ?',
        [id, actor.firmId],
      );
      if (was?.data[column] case final String date) {
        await _guardDate(table, id, date, _describe(table, was!.data));
      }
      return;
    }
    final status = values['status'];
    final undoes = status == 'void';
    if (!undoes && status != 'posted' && !values.containsKey(column)) return;
    final was = await selectOne(
      'SELECT * FROM $table WHERE id = ? AND firm_id = ?',
      [id, actor.firmId],
    );
    // Missing, the update itself refuses in words.
    if (was == null) return;
    final row = was.data;
    if (table == 'documents' && _offTheBooks.contains(row['doc_type'])) return;
    final moved = values.containsKey(column) && values[column] != row[column];
    if (!moved && (status == null || status == row['status'])) return;
    final dates = <String>{
      if (row[column] case final String d) d,
      if (values[column] case final String d) d,
    };
    for (final date in dates) {
      await _guardDate(table, id, date, _describe(table, row, undoing: undoes));
    }
  }

  /// Notes a row dated inside closed books. Judged at commit, once the
  /// whole act is known, so the refusal names what the shopkeeper did -- the
  /// bill they cancelled -- rather than whichever of its rows came first,
  /// which for a cancel is the tender at the counter.
  Future<void> _guardDate(
    String table,
    String id,
    String date,
    String what,
  ) async {
    final locks = await bookLocks();
    if (!locks.closes(date)) return;
    _inClosedBooks.add((table: table, id: id, date: date, what: what));
  }

  Approval? _approval(ApprovalKind kind) =>
      _approvals.where((a) => a.kind == kind).firstOrNull;

  /// A row as the refusal names it: "Sale bill INV-0007", "Cancelling
  /// receipt RCPT-0003".
  static String _describe(
    String table,
    Map<String, Object?> row, {
    bool undoing = false,
  }) {
    final what = switch (table) {
      'documents' => switch (row['doc_type']) {
        'sale_invoice' => 'Sale bill',
        'sale_return' => 'Sale return',
        'purchase_bill' => 'Purchase',
        'purchase_return' => 'Return to a supplier',
        'expense' => 'Expense',
        'other_income' => 'Charge',
        'delivery_challan' => 'Delivery challan',
        _ => 'Paper',
      },
      'payments' => 'Payment',
      'journal_entries' => 'Journal entry',
      'qist_plans' => 'Qist plan', // M50
      'warranty_claims' => 'Warranty claim', // M50
      'attendance' => 'The staff register', // M65
      'salary_slips' => 'Salary slip', // M65
      _ => 'A stock movement',
    };
    final no =
        row['doc_no'] ??
        row['payment_no'] ??
        row['entry_no'] ??
        row['slip_no']; // M65
    final named = no is String ? '$what $no' : what;
    return undoing
        ? 'Cancelling ${named[0].toLowerCase()}${named.substring(1)}'
        : named;
  }

  /// Refuses everything this transaction did inside closed books, or, with
  /// the owner's approval, leaves one audit row for it naming whose PIN let
  /// it in and why.
  ///
  /// Named by the bill where there is one, then the payment, so the refusal
  /// and the record's own history speak of the paper the shopkeeper knows
  /// rather than the journal entry nobody opens.
  void _checkClosedBooks() {
    if (_inClosedBooks.isEmpty) return;
    const rank = ['documents', 'payments', 'journal_entries', 'stock_ledger'];
    final first =
        ([..._inClosedBooks]..sort(
              (a, b) => rank.indexOf(a.table).compareTo(rank.indexOf(b.table)),
            ))
            .first;
    final through = _locks!.closedThrough!.value;
    final given = _approval(ApprovalKind.closedBooks);
    if (given == null) {
      throw ApprovalNeeded.closedBooks(
        closedThrough: through,
        dateLocal: first.date,
        what: first.what,
        actorUserId: actor.userId,
      );
    }
    final dates = {for (final r in _inClosedBooks) r.date}.toList()..sort();
    audit(
      action: closedBooksOverrideAction,
      entityTable: first.table,
      entityId: first.id,
      summary:
          '${first.what}, dated ${dates.first}, let into books closed up to '
          '$through by ${given.userName}: ${given.reason ?? ''}',
      after: {
        'closed_through': through,
        'dates': dates,
        'reason': given.reason,
        'approved_by': given.userId,
        'approved_by_name': given.userName,
      },
    );
  }

  /// Asks for a PIN before anything Data Lock guards may commit.
  ///
  /// Checked at commit, against the audit rows the transaction is about to
  /// leave, because every cancel, write-off and hiding leaves exactly one
  /// and no other mark this file could rely on. An owner who has just let
  /// something into closed books has given their PIN already, and is not
  /// asked twice.
  Future<void> _checkDataLock() async {
    final undoing = [
      for (final a in _audits)
        if (undoingActions.contains(a.action)) a,
    ];
    if (undoing.isEmpty) return;
    if (!(await bookLocks()).dataLock) return;
    final first = undoing.first;
    final what = first.summary ?? first.action;
    final given = _approvals.firstOrNull;
    if (given == null) {
      throw ApprovalNeeded.dataLock(what: what, actorUserId: actor.userId);
    }
    if (given.kind != ApprovalKind.dataLock) return;
    audit(
      action: dataLockPinAction,
      entityTable: first.entityTable,
      entityId: first.entityId,
      summary: 'PIN given by ${given.userName}: $what',
      after: {
        'approved_by': given.userId,
        'approved_by_name': given.userName,
        'for': first.action,
      },
    );
  }

  /// The masters whose edits are kept field by field: what a customer's
  /// phone number was before somebody changed it, and what an item's price
  /// was. Their writers name the fields they mean to change; this keeps the
  /// before of each, so every edit is kept whole without each writer having
  /// to remember to, and a writer added later cannot forget.
  static const _diffed = {'items', 'parties'};

  /// Columns worked out from others, which only repeat what changed.
  static const _derived = {'name_search'};

  Future<Map<String, Object?>?> _fieldsBefore(
    String table,
    String id,
    Map<String, Object?> values,
  ) async {
    if (!_diffed.contains(table)) return null;
    final columns = [
      for (final c in values.keys)
        if (!_derived.contains(c)) c,
    ];
    if (columns.isEmpty) return null;
    final row = await selectOne(
      'SELECT ${columns.join(', ')} FROM $table '
      'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
      [id, actor.firmId],
    );
    return row?.data;
  }

  void _noteDiff(
    String table,
    String id,
    Map<String, Object?> before,
    Map<String, Object?> values,
  ) {
    final diff = _diffs.putIfAbsent(
      '$table/$id',
      () => (before: <String, Object?>{}, after: <String, Object?>{}),
    );
    for (final e in before.entries) {
      final now = switch (values[e.key]) {
        final bool b => b ? 1 : 0,
        final Object? v => v,
      };
      // A picture or anything else that is not a plain value says nothing
      // a person could read, and would not survive JSON.
      if (now is! String? && now is! int?) continue;
      diff.before.putIfAbsent(e.key, () => e.value);
      diff.after[e.key] = now;
    }
  }

  /// Puts each master's before and after on the audit row written about it,
  /// keeping whatever the writer set itself.
  void _mergeDiffs() {
    if (_diffs.isEmpty) return;
    for (var i = 0; i < _audits.length; i++) {
      final a = _audits[i];
      final diff = _diffs['${a.entityTable}/${a.entityId}'];
      if (diff == null) continue;
      final changed = [
        for (final k in diff.after.keys)
          if (diff.before[k] != diff.after[k]) k,
      ];
      if (changed.isEmpty) continue;
      _audits[i] = a.withChanges(
        before: {for (final k in changed) k: diff.before[k], ...?a.before},
        after: {for (final k in changed) k: diff.after[k], ...?a.after},
      );
    }
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
    final rows = await select('''
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
      ''', ids);

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
          detail:
              'lines total $actualDebit but the entry declares '
              '$declaredDebit debit and $declaredCredit credit',
        );
      }
    }
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  void _noteJournalTouch(String table, String id, Map<String, Object?> row) {
    if (table == 'journal_entries') {
      _touchedJournalEntries.add(id);
    } else if (table == 'journal_lines') {
      final entry = row['journal_entry_id'];
      if (entry is String) _touchedJournalEntries.add(entry);
    }
  }

  /// Appends the outbox entry for one write.
  ///
  /// A picture's bytes stay out of it (M60). `jsonEncode` writes a
  /// `Uint8List` as a list of numbers, three or four characters for every
  /// byte, so each photograph was being kept a second time in the outbox at
  /// four times its size — a parchi of 190 KB became 900 KB of the backup —
  /// and no other device could take the row in anyway: a list arrives where
  /// a blob belongs, SQLite refuses it, and the whole merge rolled back with
  /// it. Pictures stay on the phone they were taken on (the sync store says
  /// so); the entry still says one was written, by whom and when.
  Future<void> _recordChange({
    required String table,
    required String entityId,
    required String op,
    required Map<String, Object?> payload,
    required String hlc,
    required int rev,
  }) async {
    final outbound = {
      for (final e in payload.entries)
        if (e.value is! Uint8List) e.key: e.value,
    };
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
        jsonEncode(outbound),
        hlc,
        rev,
        actor.epochMillis,
      ],
    );
  }

  Future<void> _writeAudit(_PendingAudit audit) async {
    // Into the outbox as well, so the owner's activity log on the master
    // shows what was done at every counter, not only at the master.
    final id = _ids.next();
    final hlc = _hlc.next().value;
    final row = <String, Object?>{
      'id': id,
      'firm_id': actor.firmId,
      'created_at_utc': actor.epochMillis,
      'updated_at_utc': actor.epochMillis,
      'created_by': actor.userId,
      'updated_by': actor.userId,
      'deleted_at_utc': null,
      'origin_device_id': actor.deviceId,
      'hlc': hlc,
      'rev': 1,
      'action_code': audit.action,
      'entity_table': audit.entityTable,
      'entity_id': audit.entityId,
      'summary': audit.summary,
      'before_json': audit.before == null ? null : jsonEncode(audit.before),
      'after_json': audit.after == null ? null : jsonEncode(audit.after),
      'amount_paisa': audit.amountPaisa,
      'at_utc': actor.epochMillis,
    };
    final columns = row.keys.toList();
    await _db.customStatement(
      'INSERT INTO audit_log (${columns.join(', ')}) '
      'VALUES (${List.filled(columns.length, '?').join(', ')})',
      _checked([for (final c in columns) row[c]]),
    );
    await _recordChange(
      table: 'audit_log',
      entityId: id,
      op: 'insert',
      payload: row,
      hlc: hlc,
      rev: 1,
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
  /// `Uint8List` is allowed because `attachments.bytes` is a real BLOB
  /// column: an item photograph, a cheque image, the bank QR a shopkeeper
  /// imported. The rule here has never been "scalars only" — it is that a
  /// `double` must never reach a money column, and a blob is not a number that
  /// can round.
  static List<Object?> _checked(List<Object?> args) {
    for (final a in args) {
      if (a == null || a is int || a is String || a is bool) continue;
      if (a is Uint8List) continue;
      throw ArgumentError.value(
        a,
        'args',
        'only int, String, bool, Uint8List and null may be written — a '
            'double here would be money represented as a float',
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
      else if (a is Uint8List)
        Variable<Uint8List>(a)
      else
        throw ArgumentError.value(
          a,
          'args',
          'only int, String, bool, Uint8List and null may be bound — a '
              'double here would be money represented as a float',
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

  _PendingAudit withChanges({
    required Map<String, Object?> before,
    required Map<String, Object?> after,
  }) => _PendingAudit(
    action: action,
    entityTable: entityTable,
    entityId: entityId,
    summary: summary,
    amountPaisa: amountPaisa,
    before: before,
    after: after,
  );
}
