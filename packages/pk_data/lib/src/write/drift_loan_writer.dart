import 'package:pk_domain/pk_domain.dart';

import '../read/drift_loan_reads.dart' show loanPostingFrom, loanPostingsSql;
import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// Loans the shop has taken, written through the one write path (M48).
///
/// A loan is an account of the chart and two or three entries a month; what
/// this adds over a journal voucher is that the accounts are found or made
/// for the shopkeeper, the split between principal and interest is checked
/// against what is still owed, and every line carries the loan's tag so the
/// statement can find it again. See `loans.dart` in the domain for why
/// nothing new is needed in the schema.
final class DriftLoanWriter {
  const DriftLoanWriter({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  /// Takes a loan: its account under Loans, the entry that brings the money
  /// in, and its terms. Returns the loan's id, which is its account's.
  Future<String> take(
    ActorContext actor,
    LoanDraft draft,
  ) => runner.run(actor, (tx) async {
    checkLoanDraft(draft, today: actor.businessDate);
    final into = await _moneyAccount(tx, draft.intoPaymentAccountId);
    final group = await _ensureAccount(
      tx,
      key: loansGroupKey,
      name: 'Loans',
      type: 'liability',
    );
    final lender = draft.lender.trim();
    final name = await _freeName(tx, 'Loan from $lender');
    final loanId = await tx.insert('accounts', {
      'code': await _nextCode(tx, 'liability'),
      'name': name,
      'account_type': 'liability',
      'normal_side': 'credit',
      'parent_id': group,
      'is_direct': 0,
      'is_active': 1,
    });
    final fee = draft.fee.isPositive
        ? await _ensureAccount(
            tx,
            key: loanFeeKey,
            name: 'Loan Processing Fee',
            type: 'expense',
          )
        : null;
    final number = await _number(tx);
    final entry = loanTakenEntry(
      draft: draft,
      today: actor.businessDate,
      loanName: name,
      entryNo: number.formatted,
      recordedAtUtcMillis: actor.epochMillis,
      loanAccountId: loanId,
      intoAccountId: into,
      feeAccountId: fee,
    );
    final entryId = await _write(tx, entry, loanId);
    final notes = draft.notes?.trim() ?? '';
    await tx.insert('settings', {
      'setting_key': loanSettingKey(loanId),
      'setting_value': LoanTerms(
        lender: lender,
        amount: draft.amount,
        fee: draft.fee,
        takenOn: draft.takenOn,
        receiptEntryId: entryId,
        rateBp: draft.rateBp,
        termMonths: draft.termMonths,
        instalment: draft.instalment,
        notes: notes.isEmpty ? null : notes,
      ).toJson(),
      'value_type': 'json',
    });
    tx.audit(
      action: 'LOAN_TAKEN',
      entityTable: 'accounts',
      entityId: loanId,
      summary:
          '$name: Rs ${draft.amount.amountOnly} on ${draft.takenOn.value}'
          '${draft.fee.isPositive ? ', less a fee of Rs ${draft.fee.amountOnly}' : ''}',
      amountPaisa: draft.amount.inPaisa,
    );
    return loanId;
  });

  /// Pays some of a loan back. Returns the entry's number.
  Future<String> repay(ActorContext actor, RepaymentDraft draft) =>
      runner.run(actor, (tx) async {
        final loan = await _loan(tx, draft.loanId);
        if (await _isReversed(tx, loan.terms.receiptEntryId)) {
          throw LoanRefused(
            '${loan.name} was cancelled as entered by mistake. Nothing can '
            'be paid against it.',
          );
        }
        final from = await _moneyAccount(tx, draft.fromPaymentAccountId);
        final owed = await _owed(tx, draft.loanId);
        final interest = draft.interest.isPositive
            ? await _ensureAccount(
                tx,
                key: loanInterestKey,
                name: 'Loan Interest',
                type: 'expense',
              )
            : null;
        final charges = draft.charges.isPositive
            ? await _ensureAccount(
                tx,
                key: loanChargesKey,
                name: 'Loan Charges',
                type: 'expense',
              )
            : null;
        final number = await _number(tx);
        final entry = repaymentEntry(
          draft: draft,
          loanName: loan.name,
          owed: owed,
          takenOn: loan.terms.takenOn,
          today: actor.businessDate,
          entryNo: number.formatted,
          recordedAtUtcMillis: actor.epochMillis,
          loanAccountId: draft.loanId,
          fromAccountId: from,
          interestAccountId: interest,
          chargesAccountId: charges,
        );
        await _write(tx, entry, draft.loanId);
        tx.audit(
          action: 'LOAN_REPAID',
          entityTable: 'accounts',
          entityId: draft.loanId,
          summary:
              '${entry.entryNo} ${loan.name}: Rs ${draft.principal.amountOnly} '
              'off the loan, Rs ${draft.interest.amountOnly} interest, '
              'Rs ${draft.charges.amountOnly} charges',
          amountPaisa: draft.paid.inPaisa,
        );
        return entry.entryNo;
      });

  /// Cancels one entry of a loan, the loan's own or a repayment, by the
  /// opposite entry dated today. Returns the cancelling entry's number.
  Future<String> cancel(
    ActorContext actor, {
    required String loanId,
    required String entryId,
    required String reason,
  }) => runner.run(actor, (tx) async {
    final loan = await _loan(tx, loanId);
    final postings = [
      for (final r in await tx.select(loanPostingsSql, [
        actor.firmId,
        loanId,
        loanTag(loanId),
      ]))
        loanPostingFrom(r),
    ];
    final target = postings.where((p) => p.entryId == entryId).firstOrNull;
    if (target == null) {
      throw const LoanRefused('That entry is not on this loan.');
    }
    checkLoanCancel(
      entry: target,
      owedNow: await _owed(tx, loanId),
      reason: reason,
    );

    final head = (await tx.selectOne(
      'SELECT entry_no, entry_date_utc, entry_date_local, fiscal_year, '
      '       source_type, narration, total_debit_paisa, total_credit_paisa '
      'FROM journal_entries WHERE id = ? AND firm_id = ?',
      [entryId, actor.firmId],
    ))!;
    final lines = await tx.select(
      'SELECT line_no, account_id, debit_paisa, credit_paisa, party_id, '
      '       item_id, narration '
      'FROM journal_lines '
      'WHERE journal_entry_id = ? AND firm_id = ? AND deleted_at_utc IS NULL '
      'ORDER BY line_no',
      [entryId, actor.firmId],
    );
    final original = JournalEntryPosting(
      entryNo: head.read<String>('entry_no'),
      entryDateUtcMillis: head.read<int>('entry_date_utc'),
      entryDateLocal: head.read<String>('entry_date_local'),
      fiscalYear: head.read<int>('fiscal_year'),
      sourceType: head.read<String>('source_type'),
      totalDebit: Money.paisa(head.read<int>('total_debit_paisa')),
      totalCredit: Money.paisa(head.read<int>('total_credit_paisa')),
      narration: head.readNullable<String>('narration'),
      lines: [
        for (final l in lines)
          JournalLinePosting(
            lineNo: l.read<int>('line_no'),
            // The same account rows the original named, never re-resolved.
            accountSystemKey: '#${l.read<String>('account_id')}',
            debit: Money.paisa(l.read<int>('debit_paisa')),
            credit: Money.paisa(l.read<int>('credit_paisa')),
            partyId: l.readNullable<String>('party_id'),
            itemId: l.readNullable<String>('item_id'),
            narration: l.readNullable<String>('narration'),
          ),
      ],
    );
    final number = await _number(tx);
    final reversal = reverseEntry(
      original,
      actor: actor,
      number: number,
      reason: '${loan.name}, ${reason.trim()}',
    );
    await _write(tx, reversal, loanId, reverses: entryId);
    tx.audit(
      action: 'LOAN_ENTRY_CANCELLED',
      entityTable: 'journal_entries',
      entityId: entryId,
      summary:
          '${reversal.entryNo} cancels ${original.entryNo} on ${loan.name}: '
          '${reason.trim()}',
      amountPaisa: original.totalDebit.inPaisa,
    );
    return reversal.entryNo;
  });

  // ---------------------------------------------------------------------

  Future<AllocatedNumber> _number(Tx tx) async {
    final n = await sequences.allocate(
      tx,
      docType: 'journal_entry',
      fiscalYear: tx.actor.businessDate.fiscalYear,
    );
    return AllocatedNumber(
      formatted: n.formatted,
      series: n.series,
      sequence: n.sequence,
    );
  }

  /// Writes [entry] with every line tagged for [loanId]. Every account is
  /// already an id; a line naming one by key is a bug, not a lookup.
  Future<String> _write(
    Tx tx,
    JournalEntryPosting entry,
    String loanId, {
    String? reverses,
  }) async {
    final id = await tx.insert('journal_entries', {
      'entry_no': entry.entryNo,
      'entry_date_utc': entry.entryDateUtcMillis,
      'entry_date_local': entry.entryDateLocal,
      'fiscal_year': entry.fiscalYear,
      'source_type': entry.sourceType,
      // The pair, findable together for ever.
      'reverses_entry_id': reverses,
      'narration': entry.narration,
      'total_debit_paisa': entry.totalDebit.inPaisa,
      'total_credit_paisa': entry.totalCredit.inPaisa,
    });
    for (final line in entry.lines) {
      if (!line.isResolvedAccountId) {
        throw StateError(
          'A loan line names account "${line.accountSystemKey}" by key. '
          'Its accounts are resolved before it is built.',
        );
      }
      await tx.insert('journal_lines', {
        'journal_entry_id': id,
        'line_no': line.lineNo,
        'account_id': line.accountId,
        'debit_paisa': line.debit.inPaisa,
        'credit_paisa': line.credit.inPaisa,
        'party_id': line.partyId,
        'item_id': line.itemId,
        'cost_centre': loanTag(loanId),
        'narration': line.narration,
      });
    }
    return id;
  }

  /// The loan's name and terms, or a refusal when [loanId] is not a loan of
  /// this firm.
  Future<({String name, LoanTerms terms})> _loan(Tx tx, String loanId) async {
    final row = await tx.selectOne(
      'SELECT a.name, s.setting_value FROM accounts a '
      'JOIN settings s ON s.firm_id = a.firm_id AND s.setting_key = ? '
      '  AND s.deleted_at_utc IS NULL '
      'WHERE a.id = ? AND a.firm_id = ? AND a.deleted_at_utc IS NULL',
      [loanSettingKey(loanId), loanId, tx.actor.firmId],
    );
    final terms = row == null
        ? null
        : LoanTerms.fromJson(row.read<String>('setting_value'));
    if (row == null || terms == null) {
      throw const LoanRefused('That is not a loan this shop has taken.');
    }
    return (name: row.read<String>('name'), terms: terms);
  }

  Future<Money> _owed(Tx tx, String loanId) async {
    final row = await tx.selectOne(
      'SELECT COALESCE(SUM(credit_paisa - debit_paisa), 0) AS owed '
      'FROM journal_lines '
      'WHERE firm_id = ? AND account_id = ? AND deleted_at_utc IS NULL',
      [tx.actor.firmId, loanId],
    );
    return Money.paisa(row!.read<int>('owed'));
  }

  Future<bool> _isReversed(Tx tx, String entryId) async =>
      await tx.selectOne(
        'SELECT 1 FROM journal_entries WHERE firm_id = ? '
        'AND reverses_entry_id = ? AND deleted_at_utc IS NULL',
        [tx.actor.firmId, entryId],
      ) !=
      null;

  /// The account in the chart the cash drawer or the bank [paymentAccountId]
  /// posts to. Never the cheque drawer: Cheques in Hand is paper customers
  /// gave the shop, and has its own book.
  Future<String> _moneyAccount(Tx tx, String paymentAccountId) async {
    final row = await tx.selectOne(
      'SELECT pa.ledger_account_id, pa.mode_label, a.system_key '
      'FROM payment_accounts pa JOIN accounts a ON a.id = pa.ledger_account_id '
      'WHERE pa.id = ? AND pa.firm_id = ? AND pa.deleted_at_utc IS NULL '
      '  AND pa.is_active = 1',
      [paymentAccountId, tx.actor.firmId],
    );
    if (row == null) {
      throw const LoanRefused(
        'Pick the cash or the bank account it went through.',
      );
    }
    if (row.read<String>('mode_label') == 'cheque' ||
        controlAccountKeys.contains(row.readNullable<String>('system_key'))) {
      throw const LoanRefused(
        'A loan comes into the cash or a bank and is paid back from one. A '
        'cheque is recorded in the cheque drawer.',
      );
    }
    return row.read<String>('ledger_account_id');
  }

  /// The account with [key], made under the group its kind sits in when the
  /// shop has never needed it before.
  ///
  /// Made when first needed rather than shipped in the chart: a shop that
  /// never borrows never sees Loan Interest, and a shop set up before M48
  /// gets the same accounts as one set up after it.
  Future<String> _ensureAccount(
    Tx tx, {
    required String key,
    required String name,
    required String type,
  }) async {
    final held = await tx.selectOne(
      'SELECT id FROM accounts WHERE firm_id = ? AND system_key = ? '
      'AND deleted_at_utc IS NULL',
      [tx.actor.firmId, key],
    );
    if (held != null) return held.read<String>('id');
    // The root of its kind: Liabilities, or Indirect Expenses (an expense
    // root that is not direct), so borrowing costs fall below gross profit.
    final parent = await tx.selectOne(
      'SELECT id FROM accounts WHERE firm_id = ? AND account_type = ? '
      '  AND parent_id IS NULL AND system_key IS NULL AND is_direct = 0 '
      '  AND deleted_at_utc IS NULL '
      'ORDER BY code LIMIT 1',
      [tx.actor.firmId, type],
    );
    final id = await tx.insert('accounts', {
      'code': await _nextCode(tx, type),
      'name': await _freeName(tx, name),
      'account_type': type,
      'normal_side': type == 'asset' || type == 'expense' ? 'debit' : 'credit',
      'parent_id': parent?.read<String>('id'),
      'system_key': key,
      'is_direct': 0,
      'is_active': 1,
    });
    tx.audit(
      action: 'ACCOUNT_ADDED',
      entityTable: 'accounts',
      entityId: id,
      summary: '$name ($type), for loans',
    );
    return id;
  }

  /// [base], or `base (2)`, `base (3)`... whichever the chart does not have.
  /// A second loan from the same bank is a second account, and two lines on
  /// a balance sheet with one name are two lines nobody can tell apart.
  Future<String> _freeName(Tx tx, String base) async {
    for (var n = 1; ; n++) {
      final candidate = n == 1 ? base : '$base ($n)';
      final taken = await tx.selectOne(
        'SELECT 1 FROM accounts WHERE firm_id = ? AND lower(name) = lower(?) '
        'AND deleted_at_utc IS NULL',
        [tx.actor.firmId, candidate],
      );
      if (taken == null) return candidate;
    }
  }

  /// The next code of [type], after the last one the chart has: the same
  /// rule as the shop's own accounts (M26), so a loan reads in the chart
  /// like any account the shop added.
  Future<String> _nextCode(Tx tx, String type) async {
    const ranges = {
      'asset': (1000, 1999),
      'liability': (2000, 2999),
      'equity': (3000, 3999),
      'income': (4000, 4999),
      'expense': (5000, 6999),
    };
    final range = ranges[type]!;
    final codes = await tx.select(
      'SELECT code FROM accounts WHERE firm_id = ?',
      [tx.actor.firmId],
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
      throw const LoanRefused(
        'That part of the chart is full. An accountant can archive accounts '
        'nobody uses.',
      );
    }
    return '$code';
  }
}
