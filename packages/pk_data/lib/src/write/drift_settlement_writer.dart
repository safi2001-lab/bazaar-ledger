import 'package:pk_domain/pk_domain.dart';

import '../read/drift_app_queries.dart' show DriftAppQueries;
import 'chart_top_up.dart';
import 'drift_payment_writer.dart' show paymentContextOn;
import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// The drift implementation of [SettlementWriter] (M44).
///
/// One [TxRunner] transaction with the payment writer's own handle opened
/// on it, so a receipt and the discount that settles it — or a write-off —
/// are written by the code that writes every receipt, and commit together
/// or not at all.
final class DriftSettlementWriter implements SettlementWriter {
  const DriftSettlementWriter({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(SettlementWriteContext write) body,
  ) => runner.run(actor, (tx) => body(_Context(tx, sequences)));
}

final class _Context implements SettlementWriteContext {
  _Context(this._tx, this._sequences)
    : payments = paymentContextOn(_tx, sequences: _sequences);

  final Tx _tx;
  final SequenceAllocator _sequences;

  @override
  final PaymentWriteContext payments;

  @override
  ActorContext get actor => _tx.actor;

  @override
  Future<AllocatedNumber> nextNumber(String docType) async {
    final number = await _sequences.allocate(
      _tx,
      docType: docType,
      fiscalYear: actor.businessDate.fiscalYear,
    );
    return AllocatedNumber(
      formatted: number.formatted,
      series: number.series,
      sequence: number.sequence,
    );
  }

  @override
  Future<Money> owedBy(String partyId) async {
    // The khata's own figure, read inside this transaction so it already
    // counts a receipt taken a moment ago in it.
    final row = await _tx.selectOne(
      '${DriftAppQueries.partySelectSql} WHERE p.id = ? AND p.firm_id = ?',
      [partyId, actor.firmId],
    );
    if (row == null) {
      throw const AllowanceRefused('That customer is not in this khata.');
    }
    return Money.paisa(row.read<int>('balance_paisa'));
  }

  @override
  Future<({String paymentAccountId, String ledgerAccountId})> allowanceAccount(
    AllowanceKind kind,
  ) async {
    // The expense first, added to an older shop's chart the first time it
    // is needed (`chart_top_up`), as M6 added Cheques Issued.
    final ledger = (await accountsBySystemKey(_tx, {
      kind.accountKey,
    }))[kind.accountKey];
    if (ledger == null) {
      throw AllowanceRefused(
        'The chart has no ${kind.narration} account, and one archived by '
        'hand is not brought back without asking. Open Accounts and bring '
        'it back first.',
      );
    }

    // `payments.payment_account_id` is required, so the allowance is
    // written under a payment account of its own: mode `adjustment`, never
    // `cash`, so the drawer, the cash book and the day's close (which read
    // the cash accounts) never count it; and not active, so no tender sheet
    // ever offers it. One per kind, found by the account it posts to.
    final held = await _tx.selectOne(
      'SELECT id FROM payment_accounts '
      "WHERE firm_id = ? AND mode_label = 'adjustment' "
      '  AND ledger_account_id = ? AND deleted_at_utc IS NULL '
      'ORDER BY created_at_utc, id LIMIT 1',
      [actor.firmId, ledger],
    );
    if (held != null) {
      return (
        paymentAccountId: held.read<String>('id'),
        ledgerAccountId: ledger,
      );
    }
    final name = switch (kind) {
      AllowanceKind.settlementDiscount => 'Settlement discounts',
      AllowanceKind.writeOff => 'Bad debts written off',
    };
    final id = await _tx.insert('payment_accounts', {
      'name': name,
      // The schema admits cash, bank or wallet. Nothing reads the kind of
      // an inactive account; what keeps it out of the drawer is its mode.
      'account_kind': 'cash',
      'mode_label': 'adjustment',
      'ledger_account_id': ledger,
      'is_default': 0,
      'is_active': 0,
    });
    _tx.audit(
      action: 'PAYMENT_ACCOUNT_ADDED',
      entityTable: 'payment_accounts',
      entityId: id,
      summary: '$name kept apart from the drawer, first needed now',
    );
    return (paymentAccountId: id, ledgerAccountId: ledger);
  }
}
