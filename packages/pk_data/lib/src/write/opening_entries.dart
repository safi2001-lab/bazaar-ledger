import 'package:pk_domain/pk_domain.dart';

import 'document_rows.dart';
import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// The books' side of what the shop already had when it started: goods on
/// the shelf and what customers already owed.
///
/// Until M10 both were written only where they were typed -- an opening
/// stock-ledger row, a column on the party -- and never reached the
/// journal, so the Inventory and Receivables balances left them out and no
/// balance sheet read from the books could balance against the khata or
/// the shelf. Each is now posted against Opening Balances when it is
/// entered, and [postMissingOpenings] posts the ones entered before.

/// Posts the value of an item's opening stock.
Future<void> postOpeningStock(
  Tx tx, {
  required String itemId,
  required String itemName,
  required Money value,
  SequenceAllocator sequences = const SequenceAllocator(),
}) => _post(
  tx,
  sequences,
  amount: value,
  asset: 'inventory',
  itemId: itemId,
  narration: 'Opening stock of $itemName',
);

/// Posts what a party owed on the day their khata was started.
Future<void> postOpeningBalance(
  Tx tx, {
  required String partyId,
  required String partyName,
  required Money owed,
  SequenceAllocator sequences = const SequenceAllocator(),
}) => _post(
  tx,
  sequences,
  amount: owed,
  asset: 'accounts_receivable',
  partyId: partyId,
  narration: 'Opening balance of $partyName',
);

Future<void> _post(
  Tx tx,
  SequenceAllocator sequences, {
  required Money amount,
  required String asset,
  required String narration,
  String? itemId,
  String? partyId,
}) async {
  if (amount.isZero) return;
  final actor = tx.actor;
  final number = await sequences.allocate(
    tx,
    docType: 'journal_entry',
    fiscalYear: actor.businessDate.fiscalYear,
  );
  final value = amount.abs;
  // A negative opening balance is money the shop was holding for them.
  final assetDebit = amount.isPositive;
  await insertJournal(
    tx,
    null,
    JournalEntryPosting(
      entryNo: number.formatted,
      entryDateUtcMillis: actor.epochMillis,
      entryDateLocal: actor.businessDate.value,
      fiscalYear: actor.businessDate.fiscalYear,
      sourceType: 'opening',
      totalDebit: value,
      totalCredit: value,
      narration: narration,
      lines: [
        JournalLinePosting(
          lineNo: 1,
          accountSystemKey: asset,
          debit: assetDebit ? value : Money.zero,
          credit: assetDebit ? Money.zero : value,
          partyId: partyId,
          itemId: itemId,
          narration: narration,
        ),
        JournalLinePosting(
          lineNo: 2,
          accountSystemKey: 'opening_balances',
          debit: assetDebit ? Money.zero : value,
          credit: assetDebit ? value : Money.zero,
        ),
      ],
    ),
  );
}

/// Posts every opening stock value and opening balance entered before they
/// were posted. Idempotent: one already in the journal is left alone.
/// Returns how many it posted.
Future<int> postMissingOpenings(Tx tx) async {
  final firmId = tx.actor.firmId;
  var posted = 0;
  final parties = await tx.select(
    'SELECT p.id, p.name, p.opening_balance_paisa FROM parties p '
    'WHERE p.firm_id = ? AND p.opening_balance_paisa <> 0 '
    '  AND NOT EXISTS (SELECT 1 FROM journal_lines jl '
    '    JOIN journal_entries je ON je.id = jl.journal_entry_id '
    "    WHERE jl.party_id = p.id AND je.source_type = 'opening')",
    [firmId],
  );
  for (final p in parties) {
    await postOpeningBalance(
      tx,
      partyId: p.read<String>('id'),
      partyName: p.read<String>('name'),
      owed: Money.paisa(p.read<int>('opening_balance_paisa')),
    );
    posted++;
  }
  final items = await tx.select(
    'SELECT i.id, i.name, SUM(s.value_delta_paisa) AS value '
    'FROM stock_ledger s JOIN items i ON i.id = s.item_id '
    "WHERE s.firm_id = ? AND s.txn_type = 'opening' "
    '  AND s.deleted_at_utc IS NULL '
    '  AND NOT EXISTS (SELECT 1 FROM journal_lines jl '
    '    JOIN journal_entries je ON je.id = jl.journal_entry_id '
    "    WHERE jl.item_id = i.id AND je.source_type = 'opening') "
    'GROUP BY i.id HAVING SUM(s.value_delta_paisa) <> 0',
    [firmId],
  );
  for (final i in items) {
    await postOpeningStock(
      tx,
      itemId: i.read<String>('id'),
      itemName: i.read<String>('name'),
      value: Money.paisa(i.read<int>('value')),
    );
    posted++;
  }
  if (posted > 0) {
    tx.audit(
      action: 'OPENINGS_POSTED',
      entityTable: 'firms',
      entityId: firmId,
      summary:
          '$posted opening balance${posted == 1 ? '' : 's'} entered before '
          'M10 put into the books against Opening Balances',
    );
  }
  return posted;
}
