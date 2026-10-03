import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';
import '../write/tx_runner.dart';

/// A query and its arguments, run against the database or inside a write.
typedef StaffSelect =
    Future<List<QueryRow>> Function(String sql, List<Object?> args);

/// Reading the staff book (M65).
///
/// One reader for the screens and for the writer: built over the database
/// for a screen, and over the write's own transaction when the writer has
/// to know what a man owes before it lets him be paid, so the figure a
/// screen showed and the figure the books checked are read by the same SQL.
final class DriftStaffBookReads {
  DriftStaffBookReads._(this._select);

  /// Over the database, for the screens and the reports.
  factory DriftStaffBookReads(AppDatabase db) => DriftStaffBookReads._(
    (sql, args) => db.customSelect(sql, variables: _bind(args)).get(),
  );

  /// Inside a write, so it sees what the write has done so far.
  factory DriftStaffBookReads.inside(Tx tx) => DriftStaffBookReads._(tx.select);

  final StaffSelect _select;

  // ---------------------------------------------------------------------
  // The rules
  // ---------------------------------------------------------------------

  Future<StaffRules> rules(String firmId) async {
    final rows = await _select(
      'SELECT setting_key, setting_value FROM settings '
      'WHERE firm_id = ? AND setting_key IN (?, ?) AND deleted_at_utc IS NULL',
      [firmId, staffDayRuleSetting, staffCashierAttendanceSetting],
    );
    String? value(String key) => rows
        .where((r) => r.read<String>('setting_key') == key)
        .map((r) => r.read<String>('setting_value'))
        .firstOrNull;
    return StaffRules(
      dayRule: DayRule.parse(value(staffDayRuleSetting)),
      cashierMarksAttendance: value(staffCashierAttendanceSetting) == '1',
    );
  }

  // ---------------------------------------------------------------------
  // The people
  // ---------------------------------------------------------------------

  static const _employeeColumns = '''
    e.id, e.name, e.phone, e.cnic, e.kaam, e.joined_on_local, e.pay_basis,
    e.rate_paisa, e.left_on_local, e.user_id, e.is_hidden, e.note,
    u.name AS user_name
  ''';

  /// Everybody on the books, those still working first, by name; or those
  /// in the recycle bin when [hidden].
  Future<List<Employee>> employees(String firmId, {bool hidden = false}) async {
    final rows = await _select(
      'SELECT $_employeeColumns FROM employees e '
      'LEFT JOIN users u ON u.id = e.user_id '
      'WHERE e.firm_id = ? AND e.deleted_at_utc IS NULL AND e.is_hidden = ? '
      'ORDER BY (e.left_on_local IS NOT NULL), e.name COLLATE NOCASE, e.id',
      [firmId, hidden ? 1 : 0],
    );
    return [for (final r in rows) _employee(r)];
  }

  /// One man, hidden or not; null when he is not one of this shop's.
  Future<Employee?> employee(String firmId, String employeeId) async {
    final rows = await _select(
      'SELECT $_employeeColumns FROM employees e '
      'LEFT JOIN users u ON u.id = e.user_id '
      'WHERE e.firm_id = ? AND e.id = ? AND e.deleted_at_utc IS NULL',
      [firmId, employeeId],
    );
    return rows.isEmpty ? null : _employee(rows.single);
  }

  static Employee _employee(QueryRow r) => Employee(
    id: r.read<String>('id'),
    name: r.read<String>('name'),
    phone: r.readNullable<String>('phone'),
    cnic: r.readNullable<String>('cnic'),
    kaam: EmployeeKaam.parse(r.read<String>('kaam')),
    joinedOn: BusinessDate(r.read<String>('joined_on_local')),
    basis: PayBasis.parse(r.read<String>('pay_basis')),
    rate: Money.paisa(r.read<int>('rate_paisa')),
    leftOn: switch (r.readNullable<String>('left_on_local')) {
      final String d => BusinessDate(d),
      null => null,
    },
    userId: r.readNullable<String>('user_id'),
    userName: r.readNullable<String>('user_name'),
    hidden: r.read<int>('is_hidden') == 1,
    note: r.readNullable<String>('note'),
  );

  // ---------------------------------------------------------------------
  // The register
  // ---------------------------------------------------------------------

  /// [day]'s register: everybody on the payroll that day, by name, with
  /// his mark and who made it.
  Future<List<RegisterLine>> register(String firmId, BusinessDate day) async {
    final rows = await _select(
      '''
      SELECT e.id, e.name, e.kaam, e.joined_on_local, e.left_on_local,
             a.mark, u.name AS marked_by
      FROM employees e
      LEFT JOIN attendance a
        ON a.employee_id = e.id AND a.day_local = ?2
       AND a.deleted_at_utc IS NULL
      LEFT JOIN users u ON u.id = a.updated_by
      WHERE e.firm_id = ?1 AND e.deleted_at_utc IS NULL AND e.is_hidden = 0
        AND e.joined_on_local <= ?2
        AND (e.left_on_local IS NULL OR e.left_on_local >= ?2)
      ORDER BY e.name COLLATE NOCASE, e.id
      ''',
      [firmId, day.value],
    );
    return [
      for (final r in rows)
        RegisterLine(
          employee: RosterEntry(
            id: r.read<String>('id'),
            name: r.read<String>('name'),
            kaam: EmployeeKaam.parse(r.read<String>('kaam')),
            joinedOn: BusinessDate(r.read<String>('joined_on_local')),
            leftOn: switch (r.readNullable<String>('left_on_local')) {
              final String d => BusinessDate(d),
              null => null,
            },
          ),
          mark: switch (r.readNullable<String>('mark')) {
            final String m => AttendanceMark.parse(m),
            null => null,
          },
          markedBy: r.readNullable<String>('marked_by'),
        ),
    ];
  }

  /// [employeeId]'s marks from [from] to [to], by day.
  Future<Map<String, AttendanceMark>> marksOf(
    String firmId,
    String employeeId,
    BusinessDate from,
    BusinessDate to,
  ) async {
    final rows = await _select(
      'SELECT day_local, mark FROM attendance '
      'WHERE firm_id = ? AND employee_id = ? AND day_local BETWEEN ? AND ? '
      'AND deleted_at_utc IS NULL',
      [firmId, employeeId, from.value, to.value],
    );
    return {
      for (final r in rows)
        r.read<String>('day_local'): ?AttendanceMark.parse(
          r.read<String>('mark'),
        ),
    };
  }

  /// Everybody's marks from [from] to [to]: by man, then by day.
  Future<Map<String, Map<String, AttendanceMark>>> marksBetween(
    String firmId,
    BusinessDate from,
    BusinessDate to,
  ) async {
    final rows = await _select(
      'SELECT employee_id, day_local, mark FROM attendance '
      'WHERE firm_id = ? AND day_local BETWEEN ? AND ? '
      'AND deleted_at_utc IS NULL',
      [firmId, from.value, to.value],
    );
    final marks = <String, Map<String, AttendanceMark>>{};
    for (final r in rows) {
      final mark = AttendanceMark.parse(r.read<String>('mark'));
      if (mark == null) continue;
      (marks[r.read<String>('employee_id')] ??= {})[r.read<String>(
            'day_local',
          )] =
          mark;
    }
    return marks;
  }

  // ---------------------------------------------------------------------
  // Advances
  // ---------------------------------------------------------------------

  /// The Staff Advances account's id, or null in a shop that has never
  /// given one (set up before M65, and the account not yet needed).
  Future<String?> advancesAccountId(String firmId) async {
    final rows = await _select(
      'SELECT id FROM accounts WHERE firm_id = ? AND system_key = ? '
      'AND deleted_at_utc IS NULL',
      [firmId, staffAdvancesKey],
    );
    return rows.isEmpty ? null : rows.single.read<String>('id');
  }

  /// What [employeeId] owes the shop in advances now.
  Future<Money> advanceOwed(String firmId, String employeeId) async {
    final account = await advancesAccountId(firmId);
    if (account == null) return Money.zero;
    final rows = await _select(
      'SELECT COALESCE(SUM(debit_paisa - credit_paisa), 0) AS owed '
      'FROM journal_lines WHERE firm_id = ? AND account_id = ? '
      'AND cost_centre = ? AND deleted_at_utc IS NULL',
      [firmId, account, staffTag(employeeId)],
    );
    return Money.paisa(rows.single.read<int>('owed'));
  }

  /// Every line of the Staff Advances account, with whether its entry paid
  /// wages (or cancelled a payment of them). ?1 the firm, ?2 the account.
  static const _advanceLinesSql = '''
    SELECT jl.cost_centre, jl.debit_paisa, jl.credit_paisa,
           je.id AS entry_id, je.entry_no, je.entry_date_local,
           je.narration, je.reverses_entry_id,
           EXISTS (
             SELECT 1 FROM journal_entries r
             WHERE r.reverses_entry_id = je.id AND r.firm_id = ?1
               AND r.deleted_at_utc IS NULL
           ) AS reversed,
           COALESCE(
             (SELECT s.id FROM salary_slips s
              WHERE s.journal_entry_id = je.id AND s.deleted_at_utc IS NULL),
             (SELECT s.id FROM salary_slips s
              WHERE s.reversal_entry_id = je.id AND s.deleted_at_utc IS NULL)
           ) AS slip_id
    FROM journal_lines jl
    JOIN journal_entries je
      ON je.id = jl.journal_entry_id AND je.deleted_at_utc IS NULL
    WHERE jl.firm_id = ?1 AND jl.account_id = ?2 AND jl.deleted_at_utc IS NULL
  ''';

  /// Every advance [employeeId] was given and every rupee taken back, in
  /// the order the books hold them, each with what he owed after it.
  Future<List<AdvanceLine>> advanceLines(
    String firmId,
    String employeeId,
  ) async {
    final account = await advancesAccountId(firmId);
    if (account == null) return const [];
    final rows = await _select(
      '$_advanceLinesSql AND jl.cost_centre = ?3 '
      'ORDER BY je.entry_date_local, je.created_at_utc, je.id',
      [firmId, account, staffTag(employeeId)],
    );
    var owed = Money.zero;
    return [
      for (final r in rows)
        () {
          final debit = Money.paisa(r.read<int>('debit_paisa'));
          final credit = Money.paisa(r.read<int>('credit_paisa'));
          owed = owed + debit - credit;
          final slip = r.readNullable<String>('slip_id');
          final undoes = r.readNullable<String>('reverses_entry_id') != null;
          return AdvanceLine(
            entryId: r.read<String>('entry_id'),
            entryNo: r.read<String>('entry_no'),
            on: BusinessDate(r.read<String>('entry_date_local')),
            kind: switch ((slip != null, undoes)) {
              (false, false) => AdvanceLineKind.given,
              (false, true) => AdvanceLineKind.givenCancelled,
              (true, false) => AdvanceLineKind.recovered,
              (true, true) => AdvanceLineKind.recoveryCancelled,
            },
            amount: debit.isPositive ? debit : credit,
            owedAfter: owed,
            narration: r.readNullable<String>('narration'),
            slipId: slip,
            cancelled: r.read<int>('reversed') == 1,
          );
        }(),
    ];
  }

  /// What every man has been given and has given back, those who owe
  /// most first; nobody who never took an advance.
  Future<List<AdvanceBalance>> advanceBalances(String firmId) async {
    final account = await advancesAccountId(firmId);
    if (account == null) return const [];
    final rows = await _select(_advanceLinesSql, [firmId, account]);
    final given = <String, Money>{};
    final back = <String, Money>{};
    for (final r in rows) {
      final tag = r.readNullable<String>('cost_centre') ?? '';
      if (!tag.startsWith('staff:')) continue;
      final id = tag.substring(6);
      final net = Money.paisa(
        r.read<int>('debit_paisa') - r.read<int>('credit_paisa'),
      );
      if (r.readNullable<String>('slip_id') == null) {
        given[id] = (given[id] ?? Money.zero) + net;
      } else {
        back[id] = (back[id] ?? Money.zero) - net;
      }
    }
    final people = {
      for (final e in [
        ...await employees(firmId),
        ...await employees(firmId, hidden: true),
      ])
        e.id: e,
    };
    final balances = [
      for (final id in {...given.keys, ...back.keys})
        if (people[id] case final e?)
          AdvanceBalance(
            employee: e,
            given: given[id] ?? Money.zero,
            recovered: back[id] ?? Money.zero,
          ),
    ];
    balances.sort((a, b) {
      final byOwed = b.owed.compareTo(a.owed);
      return byOwed != 0 ? byOwed : a.employee.name.compareTo(b.employee.name);
    });
    return balances;
  }

  // ---------------------------------------------------------------------
  // Slips
  // ---------------------------------------------------------------------

  /// Slips, newest month first: one man's, or every man's whose month is
  /// from [fromMonth] to [toMonth].
  Future<List<SalarySlip>> slips(
    String firmId, {
    String? employeeId,
    SalaryMonth? fromMonth,
    SalaryMonth? toMonth,
  }) async {
    final where = <String>['s.firm_id = ?', 's.deleted_at_utc IS NULL'];
    final args = <Object?>[firmId];
    if (employeeId != null) {
      where.add('s.employee_id = ?');
      args.add(employeeId);
    }
    if (fromMonth != null) {
      where.add('s.month_local >= ?');
      args.add(fromMonth.code);
    }
    if (toMonth != null) {
      where.add('s.month_local <= ?');
      args.add(toMonth.code);
    }
    return _slips(where.join(' AND '), args);
  }

  /// One slip; null when it is not one of this shop's.
  Future<SalarySlip?> slip(String firmId, String slipId) async {
    final found = await _slips('s.firm_id = ? AND s.id = ?', [firmId, slipId]);
    return found.firstOrNull;
  }

  Future<List<SalarySlip>> _slips(String where, List<Object?> args) async {
    final rows = await _select('''
      SELECT s.*, e.name AS employee_name, e.phone AS employee_phone,
             je.entry_no, pa.name AS account_name, u.name AS paid_by,
             (SELECT n.slip_no FROM salary_slips n
              WHERE n.replaces_slip_id = s.id AND n.deleted_at_utc IS NULL
              ORDER BY n.created_at_utc DESC LIMIT 1) AS replaced_by
      FROM salary_slips s
      JOIN employees e ON e.id = s.employee_id
      JOIN journal_entries je ON je.id = s.journal_entry_id
      LEFT JOIN payment_accounts pa ON pa.id = s.payment_account_id
      LEFT JOIN users u ON u.id = s.created_by
      WHERE $where
      ORDER BY s.month_local DESC, s.created_at_utc DESC, s.id
      ''', args);
    if (rows.isEmpty) return const [];
    final ids = [for (final r in rows) r.read<String>('id')];
    final lineRows = await _select(
      'SELECT slip_id, kind, label, amount_paisa FROM salary_lines '
      'WHERE slip_id IN (${List.filled(ids.length, '?').join(', ')}) '
      'AND deleted_at_utc IS NULL ORDER BY slip_id, line_no',
      ids,
    );
    final lines = <String, List<SalaryLine>>{};
    for (final l in lineRows) {
      (lines[l.read<String>('slip_id')] ??= []).add(
        SalaryLine(
          kind: SalaryLineKind.parse(l.read<String>('kind')),
          label: l.read<String>('label'),
          amount: Money.paisa(l.read<int>('amount_paisa')),
        ),
      );
    }
    return [
      for (final r in rows)
        SalarySlip(
          id: r.read<String>('id'),
          slipNo: r.read<String>('slip_no'),
          employeeId: r.read<String>('employee_id'),
          employeeName: r.read<String>('employee_name'),
          employeePhone: r.readNullable<String>('employee_phone'),
          month: SalaryMonth.tryParse(r.read<String>('month_local'))!,
          paidOn: BusinessDate(r.read<String>('paid_on_local')),
          basis: PayBasis.parse(r.read<String>('pay_basis')),
          rate: Money.paisa(r.read<int>('rate_paisa')),
          dayRule: switch (r.readNullable<String>('day_rule')) {
            final String c => DayRule.parse(c),
            null => null,
          },
          basisDays: r.read<int>('basis_days'),
          tally: MonthTally(
            present: r.read<int>('present_days'),
            late: r.read<int>('late_days'),
            halfDay: r.read<int>('half_days'),
            paidLeave: r.read<int>('paid_leave_days'),
            unpaidLeave: r.read<int>('unpaid_leave_days'),
            absent: r.read<int>('absent_days'),
            unmarked: r.read<int>('unmarked_days'),
            employedDays: r.read<int>('employed_days'),
          ),
          paidHalves: r.read<int>('paid_halves'),
          figures: SalaryFigures(
            basePay: Money.paisa(r.read<int>('base_pay_paisa')),
            additions: Money.paisa(r.read<int>('additions_paisa')),
            deductions: Money.paisa(r.read<int>('deductions_paisa')),
            recovered: Money.paisa(r.read<int>('advance_recovered_paisa')),
          ),
          entryId: r.read<String>('journal_entry_id'),
          entryNo: r.read<String>('entry_no'),
          paymentAccountId: r.readNullable<String>('payment_account_id'),
          paymentAccountName: r.readNullable<String>('account_name'),
          lines: lines[r.read<String>('id')] ?? const [],
          cancelled: r.read<String>('status') == 'void',
          voidReason: r.readNullable<String>('void_reason'),
          replacesSlipId: r.readNullable<String>('replaces_slip_id'),
          replacedBySlipNo: r.readNullable<String>('replaced_by'),
          note: r.readNullable<String>('note'),
          paidBy: r.readNullable<String>('paid_by'),
        ),
    ];
  }

  /// The live slip that pays [employeeId] for [month], if one has.
  Future<String?> livePaidSlipNo(
    String firmId,
    String employeeId,
    SalaryMonth month,
  ) async {
    final rows = await _select(
      'SELECT slip_no FROM salary_slips WHERE firm_id = ? AND employee_id = ? '
      "AND month_local = ? AND status = 'paid' AND deleted_at_utc IS NULL "
      'ORDER BY created_at_utc LIMIT 1',
      [firmId, employeeId, month.code],
    );
    return rows.isEmpty ? null : rows.single.read<String>('slip_no');
  }
}

List<Variable<Object>> _bind(List<Object?> args) => [
  for (final a in args)
    switch (a) {
      null => const Variable<String>(null),
      final int i => Variable<int>(i),
      final String s => Variable<String>(s),
      final bool b => Variable<int>(b ? 1 : 0),
      _ => throw ArgumentError.value(a, 'args', 'cannot be bound'),
    },
];
