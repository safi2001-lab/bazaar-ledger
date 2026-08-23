import 'dart:async';

import 'package:crypto/crypto.dart';

import 'package:pk_domain/pk_domain.dart';

/// What became of one attempt to print.
enum PrintOutcome {
  /// The printer took every byte.
  printed,

  /// Nothing was sent — the printer was unreachable, or busy with the job
  /// before this one. Safe to send again without asking anybody.
  notSent,

  /// Some of it came out and then the link failed. NOT safe to send again on
  /// its own: paper has already moved, and a silent retry hands the customer
  /// two half-receipts and the shop two records of one sale.
  partial,

  /// A job was begun and the app never recorded how it ended, because the
  /// process died holding it.
  ///
  /// NOT the same as `notSent`, and the difference is the reason the record
  /// lives in a database. On a Transsion ROM the Boost button kills this app
  /// mid-write to a printer that has already taken 400 of 900 bytes. Paper has
  /// moved. Only the person looking at it can say what happened, so this
  /// outcome is a question, never a retry.
  unknown,
}

/// The result of a print, and what may be done about it.
final class PrintResult {
  const PrintResult({
    required this.outcome,
    required this.jobId,
    this.error,
    this.bytesWritten = 0,
  });

  final PrintOutcome outcome;
  final String jobId;
  final Object? error;
  final int bytesWritten;

  bool get ok => outcome == PrintOutcome.printed;

  /// Whether the queue may try this again by itself.
  ///
  /// Only when nothing came out. Everything else — including [unknown], which
  /// means nobody can tell — is a decision for the person holding the paper.
  bool get mayRetryAutomatically => outcome == PrintOutcome.notSent;
}

/// One printer, one job at a time, and a retry that cannot double-print.
///
/// A thermal printer has no memory and no job identity: it prints whatever
/// arrives, and asked twice it prints twice. True idempotency is therefore
/// not available at the printer, so it is arranged here instead, and the
/// arrangement is deliberately conservative:
///
///   * Jobs are serialised. Two receipts sent at once to a printer with a
///     small buffer come out interleaved, which is worse than either coming
///     out late.
///   * A job that already printed is never sent again by the queue. A
///     shopkeeper asking for a reprint is a different thing entirely and goes
///     through a different door.
///   * A job that failed with nothing written is retried, up to a few times.
///     Nothing came out, so nobody can tell.
///   * A job that failed PART WAY is never retried automatically. Half a
///     receipt is already in someone's hand.
///
/// That last rule is the whole point. The obvious implementation retries on
/// any failure and, on a shop network with a printer that drops connections,
/// quietly produces two of every long bill.
final class PrintQueue {
  PrintQueue({
    required this.transport,
    this.log,
    this.maxAttempts = 3,
    this.retryDelay = const Duration(milliseconds: 400),
  });

  final PrinterTransport transport;

  /// Where jobs are remembered across a process death.
  ///
  /// Optional so the queue's own rules can be tested without a database, and
  /// supplied by the app always. Without it the maps below are the only
  /// record, and they do not survive Android reclaiming the app -- which is
  /// precisely when a shopkeeper reopens, taps Print, and gets a second
  /// receipt.
  final PrintJobLog? log;

  /// How many times a job that printed NOTHING may be sent again.
  final int maxAttempts;

  final Duration retryDelay;

  /// Jobs this queue has seen through to the end, by id.
  ///
  /// Kept so a caller that asks twice — a rebuilt widget, a tapped button
  /// that did not look like it worked — does not print twice.
  final _finished = <String, PrintResult>{};

  /// Jobs asked for but not yet finished, by id.
  ///
  /// Without this, three taps landing before the first print completes all
  /// find `_finished` empty, all queue, and all print — which is the exact
  /// thing this class exists to prevent, arriving through the one door the
  /// finished-jobs map cannot see. A second ask for a job already on its way
  /// waits for that job rather than starting another.
  final _pending = <String, Completer<PrintResult>>{};

  /// The job currently on the wire, so the next one waits.
  Future<void> _busy = Future<void>.value();

  /// Whether [jobId] has already been printed by this queue.
  bool hasPrinted(String jobId) =>
      _finished[jobId]?.outcome == PrintOutcome.printed;

  /// Sends [bytes] as job [jobId], once.
  ///
  /// Asking again with the same [jobId] returns the first answer without
  /// touching the printer. That is what makes a double-tapped Print button
  /// produce one receipt.
  ///
  /// When [actor] is given and a [log] is configured, the job is recorded
  /// before the first byte and its outcome after, so the answer survives the
  /// app being killed. Without both, the queue is in-memory only.
  Future<PrintResult> submit({
    required String jobId,
    required PrinterTarget target,
    required List<int> bytes,
    ActorContext? actor,
    String? documentId,
    int columnsUsed = 48,
    int copyIndex = 1,
  }) {
    // Anything already decided stands, whatever it was decided to be.
    //
    // This used to short-circuit only on `printed`. A job that ended `partial`
    // was stored here and then RE-SENT on the next submit -- from a rebuilt
    // widget, or from a shopkeeper tapping again after a failure -- which is
    // the exact double-print this class exists to prevent, arriving through
    // the one door its own doc comment promised was shut.
    final already = _finished[jobId];
    if (already != null && already.outcome != PrintOutcome.notSent) {
      return Future.value(already);
    }

    final pending = _pending[jobId];
    if (pending != null) return pending.future;

    // Chained rather than run: whatever is on the wire finishes first.
    final completer = Completer<PrintResult>();
    _pending[jobId] = completer;
    // Deliberately not awaited here. `_busy` IS the chain — awaiting it would
    // make every caller wait for every earlier job before even being told
    // theirs was accepted, and the caller already has its own future.
    final chained = _busy.then((_) async {
      final result = await _runRecorded(
        jobId: jobId,
        target: target,
        bytes: bytes,
        actor: actor,
        documentId: documentId,
        columnsUsed: columnsUsed,
        copyIndex: copyIndex,
      );
      _finished[jobId] = result;
      _pending.remove(jobId);
      completer.complete(result);
    });
    _busy = chained;
    unawaited(chained);
    return completer.future;
  }

  /// Consults the durable record, prints, and writes the outcome back.
  ///
  /// Without a log this is just [_run]. With one, the ordering is the whole
  /// mechanism: the row is committed BEFORE the first byte, so a row still
  /// saying it is sending at next launch is how the app knows it does not
  /// know.
  Future<PrintResult> _runRecorded({
    required String jobId,
    required PrinterTarget target,
    required List<int> bytes,
    required ActorContext? actor,
    required String? documentId,
    required int columnsUsed,
    required int copyIndex,
  }) async {
    final log = this.log;
    if (log == null || actor == null) {
      return _run(jobId, target, bytes);
    }

    final previous = await log.byKey(actor.firmId, jobId);
    if (previous != null && !previous.mayRetryAutomatically) {
      return PrintResult(
        outcome: switch (previous.status) {
          PrintJobStatus.printed => PrintOutcome.printed,
          PrintJobStatus.partial => PrintOutcome.partial,
          PrintJobStatus.sending => PrintOutcome.unknown,
          PrintJobStatus.failed => PrintOutcome.notSent,
        },
        jobId: jobId,
        bytesWritten: previous.bytesWritten,
      );
    }

    if (previous == null) {
      await log.begin(
        actor,
        jobKey: jobId,
        transportKind: transport.kind,
        targetAddress: target.address,
        columnsUsed: columnsUsed,
        copyIndex: copyIndex,
        byteCount: bytes.length,
        payloadSha256: _digest(bytes),
        documentId: documentId,
      );
    }

    final result = await _run(jobId, target, bytes);
    await log.finish(
      actor,
      jobKey: jobId,
      status: switch (result.outcome) {
        PrintOutcome.printed => PrintJobStatus.printed,
        PrintOutcome.partial => PrintJobStatus.partial,
        PrintOutcome.notSent => PrintJobStatus.failed,
        // _run never returns this: a job is only unknown after a process
        // death, which by definition records nothing.
        PrintOutcome.unknown => PrintJobStatus.partial,
      },
      bytesWritten: result.bytesWritten,
      failureReason: result.error?.toString(),
    );
    return result;
  }

  Future<PrintResult> _run(
    String jobId,
    PrinterTarget target,
    List<int> bytes,
  ) async {
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await transport.send(target, bytes);
        return PrintResult(outcome: PrintOutcome.printed, jobId: jobId);
      } on PrinterException catch (error) {
        lastError = error;
        if (!error.isSafeToRetry) {
          // Paper has moved. Stop, and let a person decide.
          return PrintResult(
            outcome: PrintOutcome.partial,
            jobId: jobId,
            error: error,
            bytesWritten: error.bytesWritten,
          );
        }
        if (attempt < maxAttempts) await Future<void>.delayed(retryDelay);
      } on Object catch (error) {
        // A transport that threw something other than PrinterException has
        // not told us whether paper moved, so it is treated as though it
        // might have. Assuming the safe-to-retry case here is how a bug in a
        // transport becomes a double-printed bill.
        return PrintResult(
          outcome: PrintOutcome.partial,
          jobId: jobId,
          error: error,
        );
      }
    }

    return PrintResult(
      outcome: PrintOutcome.notSent,
      jobId: jobId,
      error: lastError,
    );
  }

  /// Forgets a job, so it may be printed again.
  ///
  /// For the reprint button, which is a deliberate act by a person who can
  /// see whether the first one came out. Only the in-memory record is
  /// dropped; the durable row stays, because the history of what came out of
  /// this printer is not something a button should erase. A deliberate
  /// reprint uses a new copy index, and therefore a new job key.
  void forget(String jobId) => _finished.remove(jobId);
}

/// SHA-256 of the bytes, so a reprint at a different column width is visibly a
/// different piece of paper rather than the same job asked for twice.
String _digest(List<int> bytes) => sha256.convert(bytes).toString();
