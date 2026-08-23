import 'dart:async';

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
  /// Only when nothing came out. Everything else is a decision for the person
  /// holding the paper.
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
    this.maxAttempts = 3,
    this.retryDelay = const Duration(milliseconds: 400),
  });

  final PrinterTransport transport;

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
  final _pending = <String, Future<PrintResult>>{};

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
  Future<PrintResult> submit({
    required String jobId,
    required PrinterTarget target,
    required List<int> bytes,
  }) {
    final already = _finished[jobId];
    if (already != null && already.outcome == PrintOutcome.printed) {
      return Future.value(already);
    }

    final pending = _pending[jobId];
    if (pending != null) return pending;

    // Chained rather than run: whatever is on the wire finishes first.
    final completer = Completer<PrintResult>();
    _pending[jobId] = completer.future;
    _busy = _busy.then((_) async {
      final result = await _run(jobId, target, bytes);
      _finished[jobId] = result;
      _pending.remove(jobId);
      completer.complete(result);
    });
    return completer.future;
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
  /// see whether the first one came out.
  void forget(String jobId) => _finished.remove(jobId);
}
