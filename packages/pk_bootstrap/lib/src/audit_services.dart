part of 'app_services.dart';

/// Who changed what and when, a day once closed staying closed, and a PIN
/// before anything is undone (M42).
///
/// The locks themselves are kept by the one write path, which refuses a row
/// dated inside closed books and a cancel under Data Lock whichever screen
/// asked for it. This is the rest: setting them (the owner only), reading a
/// record's history (whoever may read the activity log), and the one place
/// a PIN given at the prompt is checked against its hash before the write
/// path is told to go ahead.
final class AuditServices {
  AuditServices._(this._app);

  final AppServices _app;

  /// Shows the PIN prompt. The app's shell sets it while it is on screen;
  /// with none set, a write that needs a PIN is refused in words, which is
  /// the right answer for a test, a tool, or the screen shown when the
  /// books would not open.
  ApprovalPrompt? prompt;

  RecordHistoryReads get _reads => DriftRecordHistory(_app.database);

  String get _firmId {
    final id = _app._identity;
    if (id == null) {
      throw StateError('This device has no shop yet.');
    }
    return id.firmId;
  }

  // ---------------------------------------------------------------------
  // History
  // ---------------------------------------------------------------------

  /// Everything that happened to [record] and what is tied to it, oldest
  /// first. Under the activity log's permission: what a bill went through
  /// is the same question as who did what.
  Future<List<HistoryEvent>> history(RecordRef record) {
    _app.require(Permission.audit);
    return _reads.historyOf(_firmId, record);
  }

  /// M54: [documentId] left the phone [via] its send sheet — written on its
  /// history as an audit row, with who and when, in a transaction of its
  /// own. Open to whoever may send it: a cashier who sends a bill on
  /// WhatsApp is the one the owner will want to ask about it.
  ///
  /// Nothing else is written: no row of the books moves, so a bill in
  /// closed books (M42) is shared and recorded like any other, and Data
  /// Lock never asks for a PIN to send one.
  Future<void> recordShared(String documentId, SharedVia via) async {
    final firmId = _firmId;
    await _app._runner.run(_app.actorNow(), (tx) async {
      final doc = await tx.selectOne(
        'SELECT doc_no FROM documents WHERE id = ? AND firm_id = ? '
        'AND deleted_at_utc IS NULL',
        [documentId, firmId],
      );
      if (doc == null) return;
      tx.audit(
        action: via.action,
        entityTable: 'documents',
        entityId: documentId,
        summary: '${doc.read<String>('doc_no')}: ${via.words}',
        after: {'via': via.name},
      );
    });
  }

  // ---------------------------------------------------------------------
  // The locks
  // ---------------------------------------------------------------------

  /// Whether whoever is signed in is an owner, who alone may set the locks.
  bool get isOwner =>
      _app.can(Permission.settings) &&
      (_app.currentUser?.role ?? Role.owner) == Role.owner;

  void _requireOwner() {
    _app.require(Permission.settings);
    if (!isOwner) {
      throw const PermissionDenied(
        Permission.settings,
        'Only the owner can close the books or change Data Lock.',
      );
    }
  }

  /// The locks as the books hold them now.
  Future<BookLocks> locks() async {
    final id = _app._identity;
    if (id == null) return BookLocks.none;
    final rows = await _app.database
        .customSelect(
          'SELECT setting_key, setting_value FROM settings '
          'WHERE firm_id = ? AND setting_key IN (?, ?) '
          'AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(id.firmId),
            const Variable<String>(booksClosedThroughSetting),
            const Variable<String>(dataLockSetting),
          ],
        )
        .get();
    String? value(String key) => rows
        .where((r) => r.read<String>('setting_key') == key)
        .map((r) => r.read<String>('setting_value'))
        .firstOrNull;
    final through = value(booksClosedThroughSetting);
    return BookLocks(
      closedThrough: through == null ? null : BusinessDate.tryParse(through),
      dataLock: value(dataLockSetting) == '1',
    );
  }

  /// The day the books are best closed up to: the last day closed at the
  /// drawer (M9), or else the end of last month.
  Future<BusinessDate> suggestedCloseDate() async {
    final today = BusinessDate.now(_app.clock);
    final closed = await _reads.lastDayClosed(_firmId);
    if (closed != null) return BusinessDate(closed);
    return BusinessDate.fromUtc(
      DateTime.utc(today.year, today.month),
    ).addDays(-1);
  }

  /// Closes the books up to [through], or opens them all again when it is
  /// null. Owner only.
  ///
  /// Moving the date back, or clearing it, is reopening, and is one of the
  /// acts Data Lock guards: a closed month quietly reopened is the first
  /// thing anybody covering their tracks would do.
  Future<void> closeBooksThrough(BusinessDate? through) async {
    _requireOwner();
    final today = BusinessDate.now(_app.clock);
    if (through != null && through.value.compareTo(today.value) > 0) {
      throw const PermissionDenied(
        Permission.settings,
        'A day that has not come yet cannot be closed.',
      );
    }
    final actor = _app.actorNow();
    await _app._runner.run(actor, (tx) async {
      // Read first, and kept: the commit's Data Lock check is judged by the
      // lock as it stood before this changed it.
      final was = await tx.bookLocks();
      final before = was.closedThrough;
      final reopening =
          before != null &&
          (through == null || through.value.compareTo(before.value) < 0);
      final id = await _setting(tx, booksClosedThroughSetting, through?.value);
      tx.audit(
        action: reopening ? booksReopenedAction : booksClosedAction,
        entityTable: 'settings',
        entityId: id,
        summary: through == null
            ? 'Books opened again (they were closed up to ${before?.value})'
            : reopening
            ? 'Books opened again after ${through.value} (they were closed '
                  'up to ${before.value})'
            : 'Books closed up to ${through.value}',
        before: {'closed_through': before?.value},
        after: {'closed_through': through?.value},
      );
    });
  }

  /// Turns Data Lock on or off. Owner only, and on only once the owner has
  /// a PIN of their own: a lock whose key nobody holds would ask for a PIN
  /// nobody could give.
  Future<void> setDataLock({required bool on}) async {
    _requireOwner();
    final me = _app.currentUser;
    if (on && (me == null || !me.hasPin)) {
      throw const PermissionDenied(
        Permission.settings,
        'Set your own PIN first: Data Lock asks for it.',
      );
    }
    final actor = _app.actorNow();
    await _app._runner.run(actor, (tx) async {
      final was = await tx.bookLocks();
      if (was.dataLock == on) return;
      final id = await _setting(tx, dataLockSetting, on ? '1' : '0');
      tx.audit(
        action: on ? dataLockOnAction : dataLockOffAction,
        entityTable: 'settings',
        entityId: id,
        summary: on
            ? 'Data Lock on: a PIN before anything is cancelled'
            : 'Data Lock off',
      );
    });
  }

  /// Entries from the shop's other counters dated inside closed books that
  /// reached this phone after the books were closed. Accepted — they were
  /// made before that counter knew — and shown here for the owner to look
  /// at, since the closed figures no longer include everything dated then.
  Future<List<LateArrival>> lateArrivals() async {
    _requireOwner();
    final now = await locks();
    return [
      for (final a in await _reads.lateArrivals(_firmId))
        if (now.closes(a.dateLocal)) a,
    ];
  }

  /// Asks for a PIN before [what], when Data Lock is on, for an act that
  /// does not pass through the write path: restoring a backup over the
  /// books. Throws [ApprovalNeeded] when none was given.
  Future<void> confirmUndo(String what) async {
    if (!(await locks()).dataLock) return;
    final actor = _app.actorNow();
    final needed = ApprovalNeeded.dataLock(
      what: what,
      actorUserId: actor.userId,
    );
    final given = await _approve(needed);
    if (given == null) throw needed;
    await _app._runner.run(actor, (tx) async {
      tx.audit(
        action: dataLockPinAction,
        entityTable: 'firms',
        entityId: actor.firmId,
        summary: 'PIN given by ${given.userName}: $what',
        after: {
          'approved_by': given.userId,
          'approved_by_name': given.userName,
          'for': what,
        },
      );
    });
  }

  /// Writes [value] under [key], updating the row if there is one. Never
  /// struck out: the key is unique per firm, tombstones included, so a lock
  /// opened again is written as an empty value instead.
  Future<String> _setting(Tx tx, String key, String? value) async {
    final held = await tx.selectOne(
      'SELECT id FROM settings WHERE firm_id = ? AND setting_key = ? '
      'AND deleted_at_utc IS NULL',
      [tx.actor.firmId, key],
    );
    if (held == null) {
      return tx.insert('settings', {
        'setting_key': key,
        'setting_value': value ?? '',
      });
    }
    final id = held.read<String>('id');
    await tx.update('settings', id, {'setting_value': value ?? ''});
    return id;
  }

  // ---------------------------------------------------------------------
  // The PIN
  // ---------------------------------------------------------------------

  /// Asks [prompt] for a PIN and checks it, until one is right or the
  /// person backs out.
  ///
  /// Closed books take the owner's PIN and a reason, and nobody else's:
  /// the owner is the one who closed them. Data Lock takes the PIN of the
  /// person doing it — their role already let them, and the PIN proves it
  /// is them at the phone and not whoever picked it up — or the owner's,
  /// standing beside them. Checked with M9's hasher against the stored
  /// hash; the digits are never kept. Wrong PINs count towards the same
  /// half-minute block as at sign-in, so the prompt is no way round it.
  Future<Approval?> _approve(ApprovalNeeded needed) async {
    final ask = prompt;
    final id = _app._identity;
    if (ask == null || id == null) return null;
    final everyone = await _app.staffStore.staff(id.firmId);
    final anyPins = everyone.any((m) => m.isActive && m.hasPin);
    final people = [
      for (final m in everyone)
        if (m.isActive &&
            (m.role == Role.owner ||
                (needed.kind == ApprovalKind.dataLock &&
                    m.id == needed.actorUserId)))
          m,
    ];
    if (people.isEmpty) return null;

    ApprovalProblem? problem;
    while (true) {
      final answer = await ask(
        ApprovalAsk(needed: needed, people: people, problem: problem),
      );
      if (answer == null) return null;
      final who = people.where((m) => m.id == answer.userId).firstOrNull;
      if (who == null) return null;
      final reason = answer.reason?.trim() ?? '';
      if (needed.kind == ApprovalKind.closedBooks && reason.isEmpty) {
        problem = ApprovalProblem.reasonNeeded;
        continue;
      }
      if (who.hasPin) {
        final blocked = _app._pinsBlockedUntil;
        if (blocked != null && _app.clock.nowUtc().isBefore(blocked)) {
          problem = ApprovalProblem.tooManyTries;
          continue;
        }
        final stored = await _app.staffStore.pinOf(id.firmId, who.id);
        final ok =
            stored != null &&
            await _app.pinHasher.verify(
              answer.pin,
              hash: stored.hash,
              salt: stored.salt,
            );
        if (!ok) {
          _app._failedPins++;
          if (_app._failedPins >= 5) {
            _app._failedPins = 0;
            _app._pinsBlockedUntil = _app.clock.nowUtc().add(
              const Duration(seconds: 30),
            );
          }
          problem = ApprovalProblem.wrongPin;
          continue;
        }
        _app._failedPins = 0;
        _app._pinsBlockedUntil = null;
      } else if (anyPins) {
        problem = ApprovalProblem.noPin;
        continue;
      }
      return Approval(
        kind: needed.kind,
        userId: who.id,
        userName: who.name,
        reason: reason.isEmpty ? null : reason,
      );
    }
  }
}
