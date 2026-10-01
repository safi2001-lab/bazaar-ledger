import 'package:pk_domain/pk_domain.dart';

import 'document_rows.dart';
import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// Closes a fiscal year into retained earnings, and keeps the shop's own
/// accounts (M26).
final class DriftYearClose {
  const DriftYearClose({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  /// Empties every income and expense account for [fiscalYear] into
  /// Retained Earnings. Closing a year again closes only what was posted
  /// into it since, so a bill entered late for June is never lost.
  Future<({String id, String entryNo})> close(
    ActorContext actor, {
    required int fiscalYear,
  }) => runner.run(actor, (tx) async {
    final end = fiscalYearEnd(fiscalYear);
    final start = '20${(fiscalYear ~/ 100).toString().padLeft(2, '0')}-07-01';
    if (actor.businessDate.value.compareTo(end) <= 0) {
      throw YearCloseRefused(
        'The year runs to $end. It can be closed from the day after.',
      );
    }
    final rows = await tx.select(
      'SELECT a.id, a.name, '
      '       SUM(jl.debit_paisa - jl.credit_paisa) AS net '
      'FROM journal_lines jl '
      'JOIN journal_entries je ON je.id = jl.journal_entry_id '
      'JOIN accounts a ON a.id = jl.account_id '
      'WHERE je.firm_id = ? AND je.entry_date_local BETWEEN ? AND ? '
      "  AND a.account_type IN ('income', 'expense') "
      '  AND je.deleted_at_utc IS NULL AND jl.deleted_at_utc IS NULL '
      'GROUP BY a.id, a.name',
      [actor.firmId, start, end],
    );
    final retained = await tx.selectOne(
      'SELECT id FROM accounts WHERE firm_id = ? '
      "AND system_key = 'retained_earnings' AND deleted_at_utc IS NULL",
      [actor.firmId],
    );
    if (retained == null) {
      throw const YearCloseRefused(
        'The chart has no Retained Earnings account to close into.',
      );
    }
    final number = await sequences.allocate(
      tx,
      docType: 'journal_entry',
      fiscalYear: actor.businessDate.fiscalYear,
    );
    final entry = yearCloseEntry(
      fiscalYear: fiscalYear,
      entryNo: number.formatted,
      entryDateUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
      retainedAccountId: retained.read<String>('id'),
      balances: [
        for (final r in rows)
          (
            accountId: r.read<String>('id'),
            name: r.read<String>('name'),
            net: Money.paisa(r.read<int>('net')),
          ),
      ],
    );
    if (entry == null) {
      throw YearCloseRefused(
        'Nothing in $start to $end is left to close: it is closed already, '
        'or nothing was earned or spent in it.',
      );
    }
    final id = await insertJournal(tx, null, entry);
    tx.audit(
      action: 'YEAR_CLOSED',
      entityTable: 'journal_entries',
      entityId: id,
      summary: entry.narration ?? 'Year closed',
      amountPaisa: entry.totalDebit.inPaisa,
    );
    return (id: id, entryNo: entry.entryNo);
  });

  /// Adds an account of the shop's own to the chart: a head of expense the
  /// shipped chart does not have, a second bank, a loan. Numbered after the
  /// last of its kind.
  Future<String> addAccount(
    ActorContext actor, {
    required String name,
    required String type,
  }) => runner.run(actor, (tx) async {
    final clean = name.trim();
    if (clean.isEmpty) {
      throw const YearCloseRefused('An account needs a name.');
    }
    const ranges = {
      'asset': (1000, 1999),
      'liability': (2000, 2999),
      'equity': (3000, 3999),
      'income': (4000, 4999),
      'expense': (5000, 6999),
    };
    final range = ranges[type];
    if (range == null) throw YearCloseRefused('Not a kind of account: $type');
    final same = await tx.selectOne(
      'SELECT 1 FROM accounts WHERE firm_id = ? AND lower(name) = lower(?) '
      'AND deleted_at_utc IS NULL',
      [actor.firmId, clean],
    );
    if (same != null) {
      throw YearCloseRefused('The chart already has an account called $clean.');
    }
    final codes = await tx.select(
      'SELECT code FROM accounts WHERE firm_id = ?',
      [actor.firmId],
    );
    var highest = range.$1;
    for (final r in codes) {
      final c = int.tryParse(r.read<String>('code'));
      if (c != null && c >= range.$1 && c <= range.$2 && c > highest) {
        highest = c;
      }
    }
    final code = highest + 10 > range.$2 ? highest + 1 : highest + 10;
    if (code > range.$2) {
      throw const YearCloseRefused('That part of the chart is full.');
    }
    final id = await tx.insert('accounts', {
      'code': '$code',
      'name': clean,
      'account_type': type,
      'normal_side': type == 'asset' || type == 'expense' ? 'debit' : 'credit',
      'is_direct': 0,
      'is_active': 1,
    });
    tx.audit(
      action: 'ACCOUNT_ADDED',
      entityTable: 'accounts',
      entityId: id,
      summary: '$code $clean ($type)',
    );
    return id;
  });
}
