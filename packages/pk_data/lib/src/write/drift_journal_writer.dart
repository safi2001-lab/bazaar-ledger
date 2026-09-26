import 'package:pk_domain/pk_domain.dart';

import 'document_rows.dart';
import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// The drift implementation of [JournalWriter].
final class DriftJournalWriter implements JournalWriter {
  const DriftJournalWriter({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(JournalWriteContext write) body,
  ) => runner.run(actor, (tx) => body(_Context(tx, sequences)));
}

final class _Context implements JournalWriteContext {
  _Context(this._tx, this._sequences);

  final Tx _tx;
  final SequenceAllocator _sequences;

  @override
  ActorContext get actor => _tx.actor;

  @override
  Future<AllocatedNumber> nextNumber(String docType) async {
    final n = await _sequences.allocate(
      _tx,
      docType: docType,
      fiscalYear: actor.businessDate.fiscalYear,
    );
    return AllocatedNumber(
      formatted: n.formatted,
      series: n.series,
      sequence: n.sequence,
    );
  }

  @override
  Future<String> apply(JournalEntryPosting entry) async {
    // The builder refuses control accounts by their key; this refuses an id
    // that is not an account of this firm at all, or one archived.
    for (final line in entry.lines) {
      final id = line.accountSystemKey.substring(1);
      final account = await _tx.selectOne(
        'SELECT system_key FROM accounts WHERE id = ? AND firm_id = ? '
        '  AND deleted_at_utc IS NULL AND is_active = 1',
        [id, actor.firmId],
      );
      if (account == null) {
        throw const VoucherRefused(
          'One of those accounts is not in the chart.',
        );
      }
      if (controlAccountKeys.contains(
        account.readNullable<String>('system_key'),
      )) {
        throw const VoucherRefused(
          'That account has its own book, and is moved from its own screen.',
        );
      }
    }
    final id = await insertJournal(_tx, null, entry);
    _tx.audit(
      action: 'JOURNAL_POSTED',
      entityTable: 'journal_entries',
      entityId: id,
      summary: 'Voucher ${entry.entryNo}: ${entry.narration}',
      amountPaisa: entry.totalDebit.inPaisa,
    );
    return id;
  }
}
