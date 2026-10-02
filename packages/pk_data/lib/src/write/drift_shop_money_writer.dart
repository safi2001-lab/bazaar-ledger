import 'dart:convert';

import 'package:pk_domain/pk_domain.dart';

import 'chart_top_up.dart' show accountsBySystemKey;
import 'document_rows.dart' show insertDocumentRows, insertJournal;
import 'drift_void_writer.dart' show voidContextOn;
import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// The shop's other income, written through the one write path (M47).
///
/// The document, its entry with every line tagged with the head, and an
/// audit row; and for putting one right, M31's void handle opened on the
/// same transaction, so an edit commits whole or not at all.
final class DriftOtherIncomeWriter implements OtherIncomeWriter {
  const DriftOtherIncomeWriter({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(OtherIncomeWriteContext write) body,
  ) => runner.run(actor, (tx) => body(_OtherIncomeContext(tx, sequences)));
}

final class _OtherIncomeContext implements OtherIncomeWriteContext {
  _OtherIncomeContext(this._tx, this._sequences)
    : documents = voidContextOn(_tx, sequences: _sequences);

  final Tx _tx;
  final SequenceAllocator _sequences;

  @override
  final VoidWriteContext documents;

  @override
  ActorContext get actor => _tx.actor;

  @override
  Future<AllocatedNumber> nextNumber(String docType) =>
      _allocate(_tx, _sequences, docType);

  @override
  Future<String?> moneyAccountFor(String paymentAccountId) =>
      _moneyAccount(_tx, paymentAccountId);

  @override
  Future<String?> incomeHeadName(String headKey) async {
    if (!isIncomeHeadKey(headKey)) return null;
    final held = await _setting(_tx, incomeHeadSettingKey(headKey));
    final name = held?['name'];
    if (name is String && name.trim().isNotEmpty) return name.trim();
    // A shipped head is the shop's whether or not it was ever renamed; one
    // of the shop's own exists only once its row does.
    return shippedIncomeHeads.contains(headKey)
        ? shippedIncomeHeadName(headKey)
        : null;
  }

  @override
  Future<RecordedOtherIncome> apply(OtherIncomePosting posting) async {
    posting.assertBalanced();
    final (documentId, _) = await insertDocumentRows(
      _tx,
      posting.document,
      const [],
    );
    final entryId = await _insertTaggedJournal(
      _tx,
      documentId,
      posting.journal,
      posting.costCentre,
    );
    _tx.audit(
      action: 'OTHER_INCOME_RECORDED',
      entityTable: 'documents',
      entityId: documentId,
      summary: posting.auditSummary,
      amountPaisa: posting.document.total.inPaisa,
    );
    return RecordedOtherIncome(
      documentId: documentId,
      docNo: posting.document.docNo,
      amount: posting.document.total,
      journalEntryId: entryId,
    );
  }

  @override
  Future<bool?> isShopIncome(String documentId) async {
    final row = await _tx.selectOne(
      'SELECT doc_type, party_id FROM documents '
      'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
      [documentId, actor.firmId],
    );
    if (row == null || row.read<String>('doc_type') != 'other_income') {
      return null;
    }
    return row.readNullable<String>('party_id') == null;
  }

  @override
  void recordCorrection(CorrectionRecord record) => _tx.audit(
    action: record.action,
    entityTable: record.entityTable,
    entityId: record.replacementId,
    summary: record.summary,
    amountPaisa: record.after.inPaisa,
    before: {
      'id': record.replacedId,
      'no': record.replacedNo,
      'amount_paisa': record.before.inPaisa,
    },
    after: {
      'id': record.replacementId,
      'no': record.replacementNo,
      'amount_paisa': record.after.inPaisa,
      'reason': record.reason,
    },
  );
}

/// Heads, monthly bills and goods taken home (M47), each through the one
/// write path with its audit row.
///
/// Heads and monthly bills are not the books. An expense head is an account
/// of the chart, and adding or renaming one moves no money; a monthly bill
/// is a reminder, kept in `settings` the way M48 keeps a loan's terms.
/// Goods taken home are the books: a document, its entry and its stock row.
final class DriftShopMoneyWriter {
  const DriftShopMoneyWriter({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  // -------------------------------------------------------------------------
  // Expense heads
  // -------------------------------------------------------------------------

  /// Adds a head of expense of the shop's own: an expense account under
  /// Direct or Indirect Expenses, numbered after the last expense account
  /// the way every account the shop adds is (M26). Returns its id.
  Future<String> addExpenseHead(
    ActorContext actor, {
    required String name,
    required bool isDirect,
  }) => runner.run(actor, (tx) async {
    final clean = await _freeAccountName(tx, name);
    // Direct or Indirect Expenses: a root with heads under it.
    final parent = await tx.selectOne(
      'SELECT g.id FROM accounts g WHERE g.firm_id = ? '
      "  AND g.account_type = 'expense' AND g.parent_id IS NULL "
      '  AND g.system_key IS NULL AND g.is_direct = ? '
      '  AND g.deleted_at_utc IS NULL '
      '  AND EXISTS (SELECT 1 FROM accounts c WHERE c.parent_id = g.id) '
      'ORDER BY g.code LIMIT 1',
      [actor.firmId, isDirect ? 1 : 0],
    );
    final code = await _nextExpenseCode(tx);
    final id = await tx.insert('accounts', {
      'code': code,
      'name': clean,
      'account_type': 'expense',
      'normal_side': 'debit',
      'parent_id': parent?.read<String>('id'),
      'is_direct': isDirect ? 1 : 0,
      'is_active': 1,
    });
    tx.audit(
      action: 'ACCOUNT_ADDED',
      entityTable: 'accounts',
      entityId: id,
      summary:
          '$code $clean (expense head, '
          '${isDirect ? 'direct' : 'indirect'})',
    );
    return id;
  });

  /// Renames the head [accountId]: the account, everywhere it is read.
  Future<void> renameExpenseHead(
    ActorContext actor, {
    required String accountId,
    required String name,
  }) => runner.run(actor, (tx) async {
    final was = await _expenseHead(tx, accountId);
    final clean = await _freeAccountName(tx, name, except: accountId);
    await tx.update('accounts', accountId, {'name': clean});
    tx.audit(
      action: 'EXPENSE_HEAD_RENAMED',
      entityTable: 'accounts',
      entityId: accountId,
      summary: '${was.name} is now called $clean',
      before: {'name': was.name},
      after: {'name': clean},
    );
  });

  /// Files the head [accountId] above the gross profit line ([isDirect]) or
  /// below it. The profit and loss reads the flag as it stands, for every
  /// period.
  Future<void> setExpenseHeadDirect(
    ActorContext actor, {
    required String accountId,
    required bool isDirect,
  }) => runner.run(actor, (tx) async {
    final was = await _expenseHead(tx, accountId);
    if (was.isDirect == isDirect) return;
    // The group of its new kind: a root with heads under it, so a head the
    // shop added beside the roots (M26 adds them unfiled) is never taken
    // for one.
    final parent = await tx.selectOne(
      'SELECT g.id FROM accounts g WHERE g.firm_id = ? '
      "  AND g.account_type = 'expense' AND g.parent_id IS NULL "
      '  AND g.system_key IS NULL AND g.is_direct = ? '
      '  AND g.deleted_at_utc IS NULL AND g.id <> ? '
      '  AND EXISTS (SELECT 1 FROM accounts c WHERE c.parent_id = g.id) '
      'ORDER BY g.code LIMIT 1',
      [actor.firmId, isDirect ? 1 : 0, accountId],
    );
    await tx.update('accounts', accountId, {
      'is_direct': isDirect ? 1 : 0,
      // Filed under the group it now belongs to, so the chart reads the
      // way the profit and loss does.
      if (parent != null) 'parent_id': parent.read<String>('id'),
    });
    tx.audit(
      action: 'EXPENSE_HEAD_FILED',
      entityTable: 'accounts',
      entityId: accountId,
      summary:
          '${was.name} is now a ${isDirect ? 'direct' : 'indirect'} expense',
      before: {'is_direct': was.isDirect ? 1 : 0},
      after: {'is_direct': isDirect ? 1 : 0},
    );
  });

  /// Stops offering the head [accountId] on the expense screen, or offers
  /// it again. Nothing in the books moves.
  Future<void> setExpenseHeadHidden(
    ActorContext actor, {
    required String accountId,
    required bool hidden,
  }) => runner.run(actor, (tx) async {
    final head = await _expenseHead(tx, accountId);
    await _putSetting(tx, expenseHeadSettingKey(accountId), {'hidden': hidden});
    tx.audit(
      action: hidden ? 'EXPENSE_HEAD_HIDDEN' : 'EXPENSE_HEAD_SHOWN',
      entityTable: 'accounts',
      entityId: accountId,
      summary:
          '${head.name} ${hidden ? 'hidden from' : 'offered on'} the '
          'expense screen',
    );
  });

  /// The head [accountId] as it stands, or a refusal when it is not one.
  Future<({String name, bool isDirect})> _expenseHead(
    Tx tx,
    String accountId,
  ) async {
    final row = await tx.selectOne(
      'SELECT a.name, a.system_key, a.is_direct, a.account_type, '
      '       (SELECT COUNT(*) FROM accounts c WHERE c.parent_id = a.id '
      '          AND c.deleted_at_utc IS NULL) AS children '
      'FROM accounts a '
      'WHERE a.id = ? AND a.firm_id = ? AND a.deleted_at_utc IS NULL',
      [accountId, tx.actor.firmId],
    );
    final key = row?.readNullable<String>('system_key');
    if (row == null ||
        row.read<String>('account_type') != 'expense' ||
        row.read<int>('children') > 0 ||
        (key != null && !expenseHeads.contains(key))) {
      throw const HeadRefused(
        'That is not one of the shop\'s expense heads. Cost of goods, '
        'wastage and the like are kept by their own rules.',
      );
    }
    return (
      name: row.read<String>('name'),
      isDirect: row.read<int>('is_direct') == 1,
    );
  }

  // -------------------------------------------------------------------------
  // Income heads
  // -------------------------------------------------------------------------

  /// Adds a head of other income of the shop's own, under [key].
  Future<void> addIncomeHead(
    ActorContext actor, {
    required String key,
    required String name,
  }) => runner.run(actor, (tx) async {
    if (!isIncomeHeadKey(key) || shippedIncomeHeads.contains(key)) {
      throw HeadRefused('"$key" cannot name a head of income.');
    }
    if (await _setting(tx, incomeHeadSettingKey(key)) != null) {
      throw HeadRefused('There is already a head of income under "$key".');
    }
    final clean = await _freeIncomeName(tx, name, except: key);
    await _putSetting(tx, incomeHeadSettingKey(key), {
      'name': clean,
      'hidden': false,
    });
    tx.audit(
      action: 'INCOME_HEAD_ADDED',
      entityTable: 'settings',
      entityId: key,
      summary: '$clean added as a head of other income',
    );
  });

  /// Renames the income head [key], shipped or the shop's own.
  Future<void> renameIncomeHead(
    ActorContext actor, {
    required String key,
    required String name,
  }) => runner.run(actor, (tx) async {
    final held = await _incomeHead(tx, key);
    final clean = await _freeIncomeName(tx, name, except: key);
    await _putSetting(tx, incomeHeadSettingKey(key), {
      'name': clean,
      'hidden': held['hidden'] == true,
    });
    tx.audit(
      action: 'INCOME_HEAD_RENAMED',
      entityTable: 'settings',
      entityId: key,
      summary: '${_incomeName(key, held)} is now called $clean',
    );
  });

  /// Stops offering the income head [key], or offers it again.
  Future<void> setIncomeHeadHidden(
    ActorContext actor, {
    required String key,
    required bool hidden,
  }) => runner.run(actor, (tx) async {
    final held = await _incomeHead(tx, key);
    await _putSetting(tx, incomeHeadSettingKey(key), {
      if (held['name'] case final String name) 'name': name,
      'hidden': hidden,
    });
    tx.audit(
      action: hidden ? 'INCOME_HEAD_HIDDEN' : 'INCOME_HEAD_SHOWN',
      entityTable: 'settings',
      entityId: key,
      summary:
          '${_incomeName(key, held)} ${hidden ? 'hidden' : 'offered again'}',
    );
  });

  Future<Map<String, Object?>> _incomeHead(Tx tx, String key) async {
    final held = await _setting(tx, incomeHeadSettingKey(key));
    if (held == null && !shippedIncomeHeads.contains(key)) {
      throw HeadRefused('"$key" is not a head of income this shop keeps.');
    }
    return held ?? const {};
  }

  static String _incomeName(String key, Map<String, Object?> held) =>
      held['name'] is String
      ? held['name']! as String
      : shippedIncomeHeadName(key);

  /// [name] trimmed, or a refusal when it is empty or another income head
  /// is already called it.
  Future<String> _freeIncomeName(
    Tx tx,
    String name, {
    required String except,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const HeadRefused('A head needs a name.');
    final taken = <String>{
      for (final k in shippedIncomeHeads)
        if (k != except) shippedIncomeHeadName(k).toLowerCase(),
    };
    for (final r in await tx.select(
      'SELECT setting_key, setting_value FROM settings '
      "WHERE firm_id = ? AND setting_key LIKE 'income.head.%' "
      '  AND deleted_at_utc IS NULL',
      [tx.actor.firmId],
    )) {
      if (r.read<String>('setting_key') == incomeHeadSettingKey(except)) {
        continue;
      }
      final held = _json(r.read<String>('setting_value'));
      if (held['name'] case final String n) taken.add(n.toLowerCase());
    }
    if (taken.contains(clean.toLowerCase())) {
      throw HeadRefused('There is already a head of income called $clean.');
    }
    return clean;
  }

  // -------------------------------------------------------------------------
  // Monthly bills
  // -------------------------------------------------------------------------

  /// Keeps [bill], new or changed.
  Future<void> saveMonthlyBill(ActorContext actor, MonthlyBill bill) =>
      runner.run(actor, (tx) async {
        checkMonthlyBill(bill);
        if (!bill.forHome && bill.headKey.startsWith('#')) {
          await _expenseHead(tx, bill.headKey.substring(1));
        }
        final key = monthlyBillSettingKey(bill.id);
        final existed = await _setting(tx, key) != null;
        await _putSettingRaw(tx, key, bill.toJson());
        tx.audit(
          action: existed ? 'MONTHLY_BILL_CHANGED' : 'MONTHLY_BILL_ADDED',
          entityTable: 'settings',
          entityId: bill.id,
          summary:
              '${bill.note}: Rs ${bill.amount.amountOnly} on day ${bill.day} '
              'of every month${bill.forHome ? ' (ghar ka kharcha)' : ''}',
          amountPaisa: bill.amount.inPaisa,
        );
      });

  /// Stops reminding about the bill [id]. The expenses it paid stay.
  Future<void> removeMonthlyBill(ActorContext actor, String id) => runner.run(
    actor,
    (tx) async {
      final row = await tx.selectOne(
        'SELECT id, setting_value FROM settings WHERE firm_id = ? '
        '  AND setting_key = ? AND deleted_at_utc IS NULL',
        [actor.firmId, monthlyBillSettingKey(id)],
      );
      if (row == null) {
        throw const MonthlyBillRefused('That monthly bill is not kept.');
      }
      final bill = MonthlyBill.fromJson(id, row.read<String>('setting_value'));
      await tx.softDelete('settings', row.read<String>('id'));
      tx.audit(
        action: 'MONTHLY_BILL_REMOVED',
        entityTable: 'settings',
        entityId: id,
        summary: '${bill?.note ?? id} no longer reminded',
      );
    },
  );

  /// Does not remind about the bill [id] again in [month] (`2026-10`).
  Future<void> skipMonthlyBill(
    ActorContext actor, {
    required String id,
    required String month,
  }) => runner.run(actor, (tx) async {
    final raw = await _settingRaw(tx, monthlyBillSettingKey(id));
    final bill = raw == null ? null : MonthlyBill.fromJson(id, raw);
    if (bill == null) {
      throw const MonthlyBillRefused('That monthly bill is not kept.');
    }
    await _putSettingRaw(
      tx,
      monthlyBillSettingKey(id),
      bill.copyWith(skippedMonth: month).toJson(),
    );
    tx.audit(
      action: 'MONTHLY_BILL_SKIPPED',
      entityTable: 'settings',
      entityId: id,
      summary: '${bill.note} not reminded again in $month',
    );
  });

  // -------------------------------------------------------------------------
  // Goods taken home
  // -------------------------------------------------------------------------

  /// Takes [draft] off the shop floor for the home, at its average cost,
  /// against the owner's drawings. One document, its entry and its stock
  /// row, so M31's cancel puts all of it back.
  Future<RecordedExpense> takeGoodsHome(
    ActorContext actor,
    GoodsTakenHomeDraft draft,
  ) => runner.run(actor, (tx) async {
    final row = await tx.selectOne(
      'SELECT i.name, i.track_stock, i.track_batch, i.track_serial, '
      '       i.avg_cost_milli_paisa, u.code AS unit_code '
      'FROM items i JOIN units u ON u.id = i.base_unit_id '
      'WHERE i.id = ? AND i.firm_id = ? AND i.deleted_at_utc IS NULL',
      [draft.itemId, actor.firmId],
    );
    if (row == null) {
      throw const ExpenseRefused('That item is not in this shop.');
    }
    // Read inside the transaction: a sale at the counter a moment ago has
    // already taken its share of the shelf.
    final held = await tx.selectOne(
      'SELECT COALESCE(SUM(qty_delta_thousandths), 0) AS q FROM stock_ledger '
      "WHERE firm_id = ? AND item_id = ? AND location_code = 'MAIN' "
      '  AND deleted_at_utc IS NULL',
      [actor.firmId, draft.itemId],
    );
    final accounts = await accountsBySystemKey(tx, {
      ownerDrawingsKey,
      'inventory',
    });
    final drawings = accounts[ownerDrawingsKey];
    final inventory = accounts['inventory'];
    if (drawings == null || inventory == null) {
      throw const ExpenseRefused(
        "The chart has no Owner's Drawings or Inventory account, so goods "
        'cannot be taken off the shelf against the owner.',
      );
    }
    final posting = goodsTakenHome(
      actor: actor,
      draft: draft,
      item: HomeGoodsItem(
        name: row.read<String>('name'),
        unitCode: row.read<String>('unit_code'),
        averageCost: Rate.raw(row.read<int>('avg_cost_milli_paisa')),
        onHand: Qty.raw(held?.read<int>('q') ?? 0),
        tracksStock: row.read<int>('track_stock') == 1,
        tracksLots:
            row.read<int>('track_batch') == 1 ||
            row.read<int>('track_serial') == 1,
      ),
      number: await _allocate(tx, sequences, 'expense'),
      journalNumber: await _allocate(tx, sequences, 'journal_entry'),
      drawingsAccountId: drawings,
      inventoryAccountId: inventory,
    );

    final (documentId, _) = await insertDocumentRows(
      tx,
      posting.document,
      const [],
    );
    final entryId = await insertJournal(tx, documentId, posting.journal);
    final movement = posting.movement;
    await tx.insert('stock_ledger', {
      'item_id': movement.itemId,
      'location_code': movement.locationCode,
      'document_id': documentId,
      'txn_type': movement.txnType,
      'qty_delta_thousandths': movement.qtyDelta.inThousandths,
      'rate_milli_paisa': movement.rate.inMilliPaisa,
      'value_delta_paisa': movement.valueDelta.inPaisa,
      'balance_after_thousandths':
          (held?.read<int>('q') ?? 0) + movement.qtyDelta.inThousandths,
      'occurred_at_utc': movement.occurredAtUtcMillis,
      'occurred_on_local': movement.occurredOnLocal,
      'reason': posting.document.notes,
    });
    tx.audit(
      action: 'GOODS_TAKEN_HOME',
      entityTable: 'documents',
      entityId: documentId,
      summary: posting.auditSummary,
      amountPaisa: posting.value.inPaisa,
    );
    return RecordedExpense(
      documentId: documentId,
      docNo: posting.document.docNo,
      amount: posting.value,
      head: ownerDrawingsKey,
      journalEntryId: entryId,
    );
  });

  // -------------------------------------------------------------------------

  /// [name] trimmed, or a refusal when it is empty or the chart already has
  /// an account called it.
  Future<String> _freeAccountName(
    Tx tx,
    String name, {
    String except = '',
  }) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const HeadRefused('A head needs a name.');
    final taken = await tx.selectOne(
      'SELECT 1 FROM accounts WHERE firm_id = ? AND lower(name) = lower(?) '
      '  AND id <> ? AND deleted_at_utc IS NULL',
      [tx.actor.firmId, clean, except],
    );
    if (taken != null) {
      throw HeadRefused('The chart already has an account called $clean.');
    }
    return clean;
  }

  /// The next expense code after the last one the chart has: the rule M26
  /// numbers the shop's own accounts by, so a head added here reads in the
  /// chart like one added there.
  Future<String> _nextExpenseCode(Tx tx) async {
    const low = 5000;
    const high = 6999;
    var highest = low;
    for (final r in await tx.select(
      'SELECT code FROM accounts WHERE firm_id = ?',
      [tx.actor.firmId],
    )) {
      final c = int.tryParse(r.read<String>('code'));
      if (c != null && c >= low && c <= high && c > highest) highest = c;
    }
    final code = highest + 10 > high ? highest + 1 : highest + 10;
    if (code > high) {
      throw const HeadRefused('The expense part of the chart is full.');
    }
    return '$code';
  }
}

// ---------------------------------------------------------------------------
// Shared
// ---------------------------------------------------------------------------

Future<AllocatedNumber> _allocate(
  Tx tx,
  SequenceAllocator sequences,
  String docType,
) async {
  final n = await sequences.allocate(
    tx,
    docType: docType,
    fiscalYear: tx.actor.businessDate.fiscalYear,
  );
  return AllocatedNumber(
    formatted: n.formatted,
    series: n.series,
    sequence: n.sequence,
  );
}

/// The chart account behind the cash drawer, a bank or a wallet, or null
/// for the cheque drawer or anything that is not one of this shop's.
Future<String?> _moneyAccount(Tx tx, String paymentAccountId) async {
  final row = await tx.selectOne(
    'SELECT pa.ledger_account_id, pa.mode_label, a.system_key '
    'FROM payment_accounts pa JOIN accounts a ON a.id = pa.ledger_account_id '
    'WHERE pa.id = ? AND pa.firm_id = ? AND pa.deleted_at_utc IS NULL '
    '  AND pa.is_active = 1 AND a.deleted_at_utc IS NULL',
    [paymentAccountId, tx.actor.firmId],
  );
  if (row == null ||
      row.read<String>('mode_label') == 'cheque' ||
      controlAccountKeys.contains(row.readNullable<String>('system_key'))) {
    return null;
  }
  return row.read<String>('ledger_account_id');
}

/// Writes [entry] against [documentId] with [tag] on every line's
/// `cost_centre`.
Future<String> _insertTaggedJournal(
  Tx tx,
  String? documentId,
  JournalEntryPosting entry,
  String? tag,
) async {
  final id = await tx.insert('journal_entries', {
    'entry_no': entry.entryNo,
    'entry_date_utc': entry.entryDateUtcMillis,
    'entry_date_local': entry.entryDateLocal,
    'fiscal_year': entry.fiscalYear,
    'source_type': entry.sourceType,
    'document_id': documentId,
    'narration': entry.narration,
    'total_debit_paisa': entry.totalDebit.inPaisa,
    'total_credit_paisa': entry.totalCredit.inPaisa,
  });
  final byKey = await accountsBySystemKey(tx, {
    for (final line in entry.lines)
      if (!line.isResolvedAccountId) line.accountSystemKey,
  });
  for (final line in entry.lines) {
    final accountId = line.isResolvedAccountId
        ? line.accountId
        : byKey[line.accountSystemKey];
    if (accountId == null) {
      throw OtherIncomeRefused(
        'This shop has no "${line.accountSystemKey}" account, so the money '
        'has nowhere to go. The chart of accounts needs checking.',
      );
    }
    await tx.insert('journal_lines', {
      'journal_entry_id': id,
      'line_no': line.lineNo,
      'account_id': accountId,
      'debit_paisa': line.debit.inPaisa,
      'credit_paisa': line.credit.inPaisa,
      'party_id': line.partyId,
      'item_id': line.itemId,
      'cost_centre': tag,
      'narration': line.narration,
    });
  }
  return id;
}

Map<String, Object?> _json(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, Object?> ? decoded : const {};
  } on FormatException {
    return const {};
  }
}

Future<String?> _settingRaw(Tx tx, String key) async {
  final row = await tx.selectOne(
    'SELECT setting_value FROM settings WHERE firm_id = ? '
    '  AND setting_key = ? AND deleted_at_utc IS NULL',
    [tx.actor.firmId, key],
  );
  return row?.read<String>('setting_value');
}

Future<Map<String, Object?>?> _setting(Tx tx, String key) async {
  final raw = await _settingRaw(tx, key);
  return raw == null ? null : _json(raw);
}

Future<void> _putSetting(Tx tx, String key, Map<String, Object?> value) =>
    _putSettingRaw(tx, key, jsonEncode(value));

/// Writes [value] under [key], over what was there.
Future<void> _putSettingRaw(Tx tx, String key, String value) async {
  final held = await tx.selectOne(
    'SELECT id FROM settings WHERE firm_id = ? AND setting_key = ? '
    '  AND deleted_at_utc IS NULL',
    [tx.actor.firmId, key],
  );
  if (held == null) {
    await tx.insert('settings', {
      'setting_key': key,
      'setting_value': value,
      'value_type': 'json',
    });
  } else {
    await tx.update('settings', held.read<String>('id'), {
      'setting_value': value,
      'value_type': 'json',
    });
  }
}
