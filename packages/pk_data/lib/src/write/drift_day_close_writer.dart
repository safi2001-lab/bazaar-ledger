import 'package:pk_domain/pk_domain.dart';

import 'document_rows.dart';
import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// The cash the books say is in the drawer, for firm `?1`: Cash in Hand, and
/// whatever account each cash tender posts into -- the same accounts the Cash
/// Book reads. Shared by the day close and the screen that previews it, so
/// the figure shown before the count is the one the close compares against.
const cashInDrawerSql =
    'SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) AS cash '
    'FROM journal_lines jl '
    'WHERE jl.firm_id = ?1 AND jl.deleted_at_utc IS NULL '
    '  AND jl.account_id IN ('
    '    SELECT id FROM accounts WHERE firm_id = ?1 '
    "      AND system_key = 'cash_in_hand' "
    '    UNION '
    '    SELECT ledger_account_id FROM payment_accounts '
    "     WHERE firm_id = ?1 AND mode_label = 'cash')";

/// The drift implementation of [DayCloseWriter].
final class DriftDayCloseWriter implements DayCloseWriter {
  const DriftDayCloseWriter({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(DayCloseWriteContext write) body,
  ) => runner.run(actor, (tx) => body(_Context(tx, sequences)));
}

final class _Context implements DayCloseWriteContext {
  _Context(this._tx, this._sequences);

  final Tx _tx;
  final SequenceAllocator _sequences;

  @override
  ActorContext get actor => _tx.actor;

  @override
  Future<Money> cashInBooks() async {
    final row = await _tx.selectOne(cashInDrawerSql, [actor.firmId]);
    return Money.paisa(row?.read<int>('cash') ?? 0);
  }

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
  Future<void> apply(DayClosePosting posting) async {
    String? entryId;
    if (posting.journal case final entry?) {
      entryId = await insertJournal(_tx, null, entry);
    }
    _tx.audit(
      action: 'DAY_CLOSED',
      entityTable: entryId == null ? 'firms' : 'journal_entries',
      entityId: entryId ?? actor.firmId,
      summary: posting.auditSummary,
      amountPaisa: posting.counted.inPaisa,
      after: {
        'expected_paisa': posting.expected.inPaisa,
        'counted_paisa': posting.counted.inPaisa,
      },
    );
  }
}
