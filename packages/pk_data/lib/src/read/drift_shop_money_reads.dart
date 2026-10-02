import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';

/// What the expense and other-income screens read (M47).
///
/// Kept apart from `DriftAppQueries`, as M48's loan reads are, so the port
/// every screen is written against does not grow a method for each of them.
final class DriftShopMoneyReads {
  const DriftShopMoneyReads(this._db);

  final AppDatabase _db;

  /// The account an expense was posted to: its entry's first debit line.
  /// The same join M3's list made; a reversal is a second entry of its own
  /// source type and never mistaken for the first.
  static const _headOf = '''
    (SELECT jl.account_id
     FROM journal_entries je
     JOIN journal_lines jl ON jl.journal_entry_id = je.id
     WHERE je.document_id = d.id AND je.source_type = 'expense'
       AND jl.debit_paisa > 0
       AND je.deleted_at_utc IS NULL AND jl.deleted_at_utc IS NULL
     ORDER BY jl.line_no LIMIT 1)
  ''';

  static String _keyOf(String accountId, String? systemKey) =>
      systemKey != null &&
          (expenseHeads.contains(systemKey) || systemKey == ownerDrawingsKey)
      ? systemKey
      : '#$accountId';

  /// Standing expenses, the shop's and the home's, newest first.
  Future<List<ExpenseBookRow>> expenseBook(
    String firmId, {
    int limit = 60,
  }) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT d.id, d.doc_no, d.doc_date_local, d.total_paisa,
                 d.balance_paisa, d.notes, p.name AS party_name,
                 a.id AS head_id, a.name AS head_name,
                 a.system_key AS head_key,
                 EXISTS (SELECT 1 FROM stock_ledger s
                         WHERE s.document_id = d.id
                           AND s.deleted_at_utc IS NULL) AS goods
          FROM documents d
          LEFT JOIN parties p ON p.id = d.party_id
          LEFT JOIN accounts a ON a.id = $_headOf
          WHERE d.firm_id = ? AND d.doc_type = 'expense'
            AND d.status = 'posted'
            AND d.deleted_at_utc IS NULL
          ORDER BY d.doc_date_local DESC, d.doc_seq DESC, d.id DESC
          LIMIT ?
          ''',
          variables: [Variable<String>(firmId), Variable<int>(limit)],
          readsFrom: {
            _db.documents,
            _db.parties,
            _db.journalEntries,
            _db.journalLines,
            _db.accounts,
            _db.stockLedger,
          },
        )
        .get();
    return [
      for (final r in rows)
        if (r.readNullable<String>('head_id') case final headId?)
          ExpenseBookRow(
            id: r.read<String>('id'),
            docNo: r.read<String>('doc_no'),
            dateLocal: r.read<String>('doc_date_local'),
            headKey: _keyOf(headId, r.readNullable<String>('head_key')),
            headName: r.read<String>('head_name'),
            headSystemKey: r.readNullable<String>('head_key'),
            amount: Money.paisa(r.read<int>('total_paisa')),
            owed: Money.paisa(r.read<int>('balance_paisa')),
            note: r.readNullable<String>('notes') ?? '',
            partyName: r.readNullable<String>('party_name'),
            forHome: r.readNullable<String>('head_key') == ownerDrawingsKey,
            goods: r.read<int>('goods') == 1,
          ),
    ];
  }

  /// Whose money one expense was, its head and its tag.
  Future<ExpenseFacts?> expenseFacts(String firmId, String documentId) async {
    final r = await _db
        .customSelect(
          '''
          SELECT d.id, a.id AS head_id, a.name AS head_name,
                 a.system_key AS head_key,
                 (SELECT jl.cost_centre
                  FROM journal_entries je
                  JOIN journal_lines jl ON jl.journal_entry_id = je.id
                  WHERE je.document_id = d.id AND je.source_type = 'expense'
                    AND jl.deleted_at_utc IS NULL
                  ORDER BY jl.line_no LIMIT 1) AS tag,
                 EXISTS (SELECT 1 FROM stock_ledger s
                         WHERE s.document_id = d.id
                           AND s.deleted_at_utc IS NULL) AS goods
          FROM documents d
          LEFT JOIN accounts a ON a.id = $_headOf
          WHERE d.id = ? AND d.firm_id = ? AND d.doc_type = 'expense'
            AND d.deleted_at_utc IS NULL
          ''',
          variables: [Variable<String>(documentId), Variable<String>(firmId)],
          readsFrom: {
            _db.documents,
            _db.journalEntries,
            _db.journalLines,
            _db.accounts,
            _db.stockLedger,
          },
        )
        .getSingleOrNull();
    final headId = r?.readNullable<String>('head_id');
    if (r == null || headId == null) return null;
    final key = r.readNullable<String>('head_key');
    return ExpenseFacts(
      documentId: documentId,
      headKey: _keyOf(headId, key),
      headName: r.read<String>('head_name'),
      headSystemKey: key,
      forHome: key == ownerDrawingsKey,
      goods: r.read<int>('goods') == 1,
      tag: r.readNullable<String>('tag'),
    );
  }

  /// What was spent from [from] to [to], the shop's and the home's apart.
  Future<MonthSplit> monthSplit(
    String firmId,
    BusinessDate from,
    BusinessDate to,
  ) async {
    final r = await _db
        .customSelect(
          '''
          SELECT COALESCE(SUM(CASE WHEN a.system_key = ?4
                                   THEN d.total_paisa END), 0) AS home,
                 COALESCE(SUM(CASE WHEN a.system_key IS NULL
                                     OR a.system_key <> ?4
                                   THEN d.total_paisa END), 0) AS shop
          FROM documents d
          LEFT JOIN accounts a ON a.id = $_headOf
          WHERE d.firm_id = ?1 AND d.doc_type = 'expense'
            AND d.status = 'posted' AND d.deleted_at_utc IS NULL
            AND d.doc_date_local BETWEEN ?2 AND ?3
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(from.value),
            Variable<String>(to.value),
            Variable<String>(ownerDrawingsKey),
          ],
          readsFrom: {
            _db.documents,
            _db.journalEntries,
            _db.journalLines,
            _db.accounts,
          },
        )
        .getSingle();
    return MonthSplit(
      shop: Money.paisa(r.read<int>('shop')),
      home: Money.paisa(r.read<int>('home')),
    );
  }

  /// Every head an expense can go under, hidden ones included: the shipped
  /// heads in the order the screen has always shown them, the shop's own
  /// after them by code, and Miscellaneous last.
  Future<List<ExpenseHead>> shopExpenseHeads(String firmId) async {
    final shipped = [for (final k in expenseHeads) Variable<String>(k)];
    final marks = List.filled(shipped.length, '?').join(', ');
    final rows = await _db
        .customSelect(
          '''
          SELECT a.id, a.code, a.name, a.system_key, a.is_direct,
                 s.setting_value AS held
          FROM accounts a
          LEFT JOIN settings s
            ON s.firm_id = a.firm_id
           AND s.setting_key = 'expense.head.' || a.id
           AND s.deleted_at_utc IS NULL
          WHERE a.firm_id = ? AND a.account_type = 'expense'
            AND a.deleted_at_utc IS NULL
            AND (a.system_key IN ($marks)
                 OR (a.system_key IS NULL
                     AND NOT EXISTS (SELECT 1 FROM accounts c
                                     WHERE c.parent_id = a.id
                                       AND c.deleted_at_utc IS NULL)))
          ORDER BY a.code
          ''',
          variables: [Variable<String>(firmId), ...shipped],
          readsFrom: {_db.accounts, _db.settings},
        )
        .get();
    final heads = [
      for (final r in rows)
        ExpenseHead(
          accountId: r.read<String>('id'),
          code: r.read<String>('code'),
          name: r.read<String>('name'),
          systemKey: r.readNullable<String>('system_key'),
          isDirect: r.read<int>('is_direct') == 1,
          hidden: _json(r.readNullable<String>('held'))['hidden'] == true,
        ),
    ];
    int rank(ExpenseHead h) => switch (h.systemKey) {
      'misc' => 2,
      final String key when expenseHeads.contains(key) => 0,
      _ => 1,
    };
    heads.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      if (rank(a) == 0) {
        return expenseHeads
            .indexOf(a.systemKey!)
            .compareTo(expenseHeads.indexOf(b.systemKey!));
      }
      return a.code.compareTo(b.code);
    });
    return heads;
  }

  /// Every head of other income, hidden ones included: the shipped heads in
  /// their order, then the shop's own by name.
  Future<List<IncomeHead>> incomeHeads(String firmId) async {
    final rows = await _db
        .customSelect(
          'SELECT setting_key, setting_value FROM settings '
          "WHERE firm_id = ? AND setting_key LIKE 'income.head.%' "
          '  AND deleted_at_utc IS NULL',
          variables: [Variable<String>(firmId)],
          readsFrom: {_db.settings},
        )
        .get();
    final held = {
      for (final r in rows)
        r
            .read<String>('setting_key')
            .substring(incomeHeadSettingKey('').length): _json(
          r.read<String>('setting_value'),
        ),
    };
    IncomeHead head(String key) {
      final h = held[key] ?? const <String, Object?>{};
      final name = h['name'];
      return IncomeHead(
        key: key,
        name: name is String && name.trim().isNotEmpty ? name.trim() : null,
        hidden: h['hidden'] == true,
      );
    }

    final own = [
      for (final key in held.keys)
        if (!shippedIncomeHeads.contains(key) && isIncomeHeadKey(key))
          head(key),
    ]..sort((a, b) => a.bookName.compareTo(b.bookName));
    return [for (final key in shippedIncomeHeads) head(key), ...own];
  }

  /// The shop's standing other income, newest first. Never a charge: those
  /// carry a party.
  Future<List<OtherIncomeRow>> otherIncomes(
    String firmId, {
    int limit = 60,
  }) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT d.id, d.doc_no, d.doc_date_local, d.total_paisa, d.notes,
                 d.party_name_snapshot, $_incomeTag AS tag
          FROM documents d
          WHERE d.firm_id = ? AND d.doc_type = 'other_income'
            AND d.party_id IS NULL
            AND d.status = 'posted' AND d.deleted_at_utc IS NULL
          ORDER BY d.doc_date_local DESC, d.doc_seq DESC, d.id DESC
          LIMIT ?
          ''',
          variables: [Variable<String>(firmId), Variable<int>(limit)],
          readsFrom: {_db.documents, _db.journalEntries, _db.journalLines},
        )
        .get();
    return [
      for (final r in rows)
        OtherIncomeRow(
          id: r.read<String>('id'),
          docNo: r.read<String>('doc_no'),
          dateLocal: r.read<String>('doc_date_local'),
          headKey: incomeHeadOfTag(r.readNullable<String>('tag')) ?? 'other',
          amount: Money.paisa(r.read<int>('total_paisa')),
          note: r.readNullable<String>('notes') ?? '',
          fromName: r.readNullable<String>('party_name_snapshot'),
        ),
    ];
  }

  /// The tag on the first line of the entry that put an income on the
  /// books.
  static const _incomeTag = '''
    (SELECT jl.cost_centre
     FROM journal_entries je
     JOIN journal_lines jl ON jl.journal_entry_id = je.id
     WHERE je.document_id = d.id AND je.source_type = 'other_income'
       AND je.deleted_at_utc IS NULL AND jl.deleted_at_utc IS NULL
     ORDER BY jl.line_no LIMIT 1)
  ''';

  /// The shop's standing other income from [from] to [to], by head.
  Future<Map<String, Money>> incomeByHead(
    String firmId,
    BusinessDate from,
    BusinessDate to,
  ) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT tag, SUM(total_paisa) AS total FROM (
            SELECT d.total_paisa, $_incomeTag AS tag
            FROM documents d
            WHERE d.firm_id = ?1 AND d.doc_type = 'other_income'
              AND d.party_id IS NULL
              AND d.status = 'posted' AND d.deleted_at_utc IS NULL
              AND d.doc_date_local BETWEEN ?2 AND ?3
          )
          GROUP BY tag
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(from.value),
            Variable<String>(to.value),
          ],
          readsFrom: {_db.documents, _db.journalEntries, _db.journalLines},
        )
        .get();
    final byHead = <String, Money>{};
    for (final r in rows) {
      final key = incomeHeadOfTag(r.readNullable<String>('tag')) ?? 'other';
      byHead[key] =
          (byHead[key] ?? Money.zero) + Money.paisa(r.read<int>('total'));
    }
    return byHead;
  }

  /// One entry of the shop's other income, standing or cancelled.
  Future<OtherIncomeDetail?> otherIncome(
    String firmId,
    String documentId,
  ) async {
    final r = await _db
        .customSelect(
          '''
          SELECT d.id, d.doc_no, d.doc_date_local, d.status, d.void_reason,
                 d.total_paisa, d.notes, d.party_name_snapshot,
                 u.name AS entered_by, $_incomeTag AS tag,
                 (SELECT pa.id
                  FROM journal_entries je
                  JOIN journal_lines jl ON jl.journal_entry_id = je.id
                  JOIN payment_accounts pa
                    ON pa.ledger_account_id = jl.account_id
                   AND pa.firm_id = d.firm_id
                   AND pa.deleted_at_utc IS NULL
                  WHERE je.document_id = d.id
                    AND je.source_type = 'other_income'
                    AND jl.debit_paisa > 0
                  ORDER BY jl.line_no, pa.is_active DESC, pa.is_default DESC,
                           pa.name
                  LIMIT 1) AS into_account
          FROM documents d
          LEFT JOIN users u ON u.id = d.created_by
          WHERE d.id = ? AND d.firm_id = ? AND d.doc_type = 'other_income'
            AND d.party_id IS NULL AND d.deleted_at_utc IS NULL
          ''',
          variables: [Variable<String>(documentId), Variable<String>(firmId)],
          readsFrom: {
            _db.documents,
            _db.users,
            _db.journalEntries,
            _db.journalLines,
            _db.paymentAccounts,
          },
        )
        .getSingleOrNull();
    if (r == null) return null;
    return OtherIncomeDetail(
      id: documentId,
      docNo: r.read<String>('doc_no'),
      dateLocal: r.read<String>('doc_date_local'),
      status: r.read<String>('status'),
      headKey: incomeHeadOfTag(r.readNullable<String>('tag')) ?? 'other',
      amount: Money.paisa(r.read<int>('total_paisa')),
      note: r.readNullable<String>('notes') ?? '',
      enteredBy: r.readNullable<String>('entered_by') ?? '',
      fromName: r.readNullable<String>('party_name_snapshot'),
      paymentAccountId: r.readNullable<String>('into_account'),
      voidReason: r.readNullable<String>('void_reason'),
    );
  }

  /// Every monthly bill the shop keeps, in the order of their day.
  Future<List<MonthlyBill>> monthlyBills(String firmId) async {
    final rows = await _db
        .customSelect(
          'SELECT setting_key, setting_value FROM settings '
          "WHERE firm_id = ? AND setting_key LIKE 'expense.recurring.%' "
          '  AND deleted_at_utc IS NULL',
          variables: [Variable<String>(firmId)],
          readsFrom: {_db.settings},
        )
        .get();
    return [
      for (final r in rows)
        ?MonthlyBill.fromJson(
          r
              .read<String>('setting_key')
              .substring(monthlyBillSettingPrefix.length),
          r.read<String>('setting_value'),
        ),
    ]..sort((a, b) {
      final byDay = a.day.compareTo(b.day);
      return byDay != 0 ? byDay : a.note.compareTo(b.note);
    });
  }

  /// The monthly-bill tags on standing expenses dated [from] to [to]: the
  /// bills paid in that span. A cancelled payment is not standing, so its
  /// bill is due again.
  Future<Set<String>> paidTags(
    String firmId,
    BusinessDate from,
    BusinessDate to,
  ) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT DISTINCT jl.cost_centre AS tag
          FROM documents d
          JOIN journal_entries je
            ON je.document_id = d.id AND je.source_type = 'expense'
          JOIN journal_lines jl ON jl.journal_entry_id = je.id
          WHERE d.firm_id = ?1 AND d.doc_type = 'expense'
            AND d.status = 'posted' AND d.deleted_at_utc IS NULL
            AND d.doc_date_local BETWEEN ?2 AND ?3
            AND jl.deleted_at_utc IS NULL
            AND jl.cost_centre LIKE 'expense:recurring:%'
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(from.value),
            Variable<String>(to.value),
          ],
          readsFrom: {_db.documents, _db.journalEntries, _db.journalLines},
        )
        .get();
    return {for (final r in rows) r.read<String>('tag')};
  }

  static Map<String, Object?> _json(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }
}
