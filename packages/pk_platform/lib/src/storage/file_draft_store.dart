import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pk_domain/pk_domain.dart';

/// A [DraftStore] that keeps each slot in its own file.
///
/// One small file, replaced whole. Not a table in the books: the ledger opens
/// with `synchronous = FULL`, which fsyncs on every commit, and that is right
/// for a posted sale and wrong for something rewritten on every barcode scan
/// on the eMMC flash of a Rs 34,000 handset. A draft that costs an fsync per
/// scan is a draft that makes the counter slower, which is the one thing the
/// eight-second bill target cannot afford.
///
/// Losing the very last write to a power cut is acceptable here and only
/// here. The threat being defended against is a ROM force-stopping the app,
/// which is process death, not power loss — the bytes are already with the
/// kernel by then and reach the disk whatever happens to the app.
final class FileDraftStore implements DraftStore {
  FileDraftStore(this.directory);

  /// Where the slots live. The caller passes the application support
  /// directory, which Android keeps out of the media scanner and out of
  /// automatic cloud backup.
  final Directory directory;

  /// One writer per slot, latest wins.
  ///
  /// A scan mutates the cart, which schedules a write. Tapping the quantity
  /// stepper four times quickly schedules four, and three of them are already
  /// stale before they start. So a write in flight holds the slot, the newest
  /// pending contents overwrite any older pending contents, and when the
  /// write finishes it picks up whatever is waiting. Bounded work, never a
  /// queue, and the last thing the cashier did is always what lands.
  final _pending = <String, String?>{};
  final _draining = <String, Completer<void>>{};

  File _fileFor(String slot) {
    if (slot.isEmpty || slot.contains(RegExp(r'[^a-z0-9_-]'))) {
      // A slot name becomes a filename, so it is checked rather than trusted.
      // Nothing in the app builds one from user input today, and this is here
      // so that it stays true when hold-bill arrives and slots start carrying
      // a counter name.
      throw ArgumentError.value(slot, 'slot', 'not a usable slot name');
    }
    return File('${directory.path}${Platform.pathSeparator}draft_$slot.json');
  }

  @override
  Future<String?> read(String slot) async {
    try {
      final file = _fileFor(slot);
      if (!file.existsSync()) return null;
      final text = await file.readAsString(encoding: utf8);
      return text.trim().isEmpty ? null : text;
    } on Object {
      // A draft that cannot be read is a draft that is not there. The app
      // still opens, and the cashier rings the bill again — annoying, and far
      // better than a counter that will not start because of a scrap of paper.
      return null;
    }
  }

  @override
  Future<void> write(String slot, String contents) => _schedule(slot, contents);

  @override
  Future<void> clear(String slot) => _schedule(slot, null);

  Future<void> _schedule(String slot, String? contents) {
    // Checked here, synchronously, so a bad slot name is a programming error
    // the caller sees at the call rather than an unhandled async error that
    // surfaces somewhere else entirely.
    _fileFor(slot);
    _pending[slot] = contents;
    final running = _draining[slot];
    if (running != null) return running.future;

    final completer = Completer<void>();
    _draining[slot] = completer;
    unawaited(_drain(slot, completer));
    return completer.future;
  }

  Future<void> _drain(String slot, Completer<void> done) async {
    try {
      while (_pending.containsKey(slot)) {
        await _writeNow(slot, _pending.remove(slot));
      }
    } finally {
      // Always, whatever happened. A drain that ends without releasing the
      // slot would leave every later write waiting on a future that never
      // completes, and the cart would stop being saved silently — which is
      // exactly the failure this store exists to prevent.
      _draining.remove(slot);
      _pending.remove(slot);
      if (!done.isCompleted) done.complete();
    }
  }

  Future<void> _writeNow(String slot, String? contents) async {
    final file = _fileFor(slot);
    try {
      if (contents == null) {
        if (file.existsSync()) await file.delete();
        return;
      }
      // Written beside the target and renamed over it. `writeAsString` on the
      // target itself truncates first, so a kill landing in the middle leaves
      // a file that exists, parses as nothing, and reads as a cart with some
      // of its lines — which the cashier cannot tell from a whole one, and
      // the missing stock walks out of the shop. A rename either happened or
      // it did not.
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(contents, encoding: utf8, flush: true);
      await temp.rename(file.path);
    } on Object {
      // A draft that cannot be saved must not take the sale down with it.
      // The cart is still in memory and the bill can still be rung; all that
      // is lost is the safety net.
    }
  }
}

/// A [DraftStore] that keeps slots in memory, for tests and for the desktop
/// harness where there is no application support directory to write into.
///
/// Deliberately not a no-op. A store that silently discards everything would
/// let a test that asserts a cart is restored pass without the cart ever
/// having been saved, which is the exact shape of the failure this whole
/// codebase exists to make impossible.
final class InMemoryDraftStore implements DraftStore {
  final _slots = <String, String>{};

  @override
  Future<String?> read(String slot) async => _slots[slot];

  @override
  Future<void> write(String slot, String contents) async =>
      _slots[slot] = contents;

  @override
  Future<void> clear(String slot) async => _slots.remove(slot);
}
