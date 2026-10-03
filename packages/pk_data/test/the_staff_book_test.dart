import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// The staff book (M65) against a real database: the day's register, a
/// month's wages worked out from it and paid, an advance given and taken
/// back off them, the books balancing after each, a slip cancelled and
/// corrected, the owner's closed books and Data Lock, and the three
/// reports.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late TxRunner runner;
  late DriftStaffBookWriter writer;
  late DriftStaffBookReads reads;
  late ReportEngine reports;
  late String cash;
  late String bilal;

  /// The shop on [day], at nine in the morning PKT.
  ActorContext on(String day) {
    final d = BusinessDate(day);
    return firm.actorAt(DateTime.utc(d.year, d.month, d.day, 4));
  }

  final september = SalaryMonth(2026, 9);

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 8, 1, 4));
    db = await openTestDatabase();
    final ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    writer = DriftStaffBookWriter(runner: runner);
    reads = DriftStaffBookReads(db);
    reports = ReportEngine(DriftReportSource(db));
    cash = (await DriftAppQueries(
      db,
    ).paymentAccounts(firm.firmId)).firstWhere((a) => a.modeLabel == 'cash').id;
    bilal = await writer.addEmployee(
      on('2026-08-01'),
      EmployeeDraft(
        name: 'Bilal',
        kaam: EmployeeKaam.salesman,
        basis: PayBasis.monthly,
        rate: Money.rupees(30000),
        joinedOn: const BusinessDate('2026-08-01'),
        cnic: '35202-1234567-1',
        phone: '0300-1234567',
      ),
    );
  });

  tearDown(() async => db.close());

  /// The balance of the account with [key], on its normal side's terms:
  /// debit less credit.
  Future<Money> balance(String key) async {
    final row = await db
        .customSelect(
          'SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) AS n '
          'FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
          'WHERE a.system_key = ? AND jl.deleted_at_utc IS NULL',
          variables: [Variable<String>(key)],
        )
        .getSingle();
    return Money.paisa(row.read<int>('n'));
  }

  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
          .read<int>('n');

  Future<void> mark(String day, Map<String, AttendanceMark> marks) =>
      writer.mark(on(day), BusinessDate(day), marks);

  /// September: two days absent, a half day, a day of paid leave, a day
  /// late; the rest unmarked, so worked.
  Future<void> markSeptember() async {
    await mark('2026-09-03', {bilal: AttendanceMark.absent});
    await mark('2026-09-04', {bilal: AttendanceMark.absent});
    await mark('2026-09-05', {bilal: AttendanceMark.halfDay});
    await mark('2026-09-07', {bilal: AttendanceMark.paidLeave});
    await mark('2026-09-08', {bilal: AttendanceMark.late});
  }

  Future<String> pay({
    SalaryMonth? month,
    String paidOn = '2026-10-01',
    int recover = 0,
    List<SalaryLine> lines = const [],
    String? employee,
  }) => writer.paySalary(
    on(paidOn),
    SalaryDraft(
      employeeId: employee ?? bilal,
      month: month ?? september,
      paidOn: BusinessDate(paidOn),
      lines: lines,
      advanceRecovered: Money.rupees(recover),
      paymentAccountId: cash,
    ),
  );

  Future<String> advance(int rupees, {String day = '2026-09-12'}) =>
      writer.giveAdvance(
        on(day),
        AdvanceDraft(
          employeeId: bilal,
          amount: Money.rupees(rupees),
          paymentAccountId: cash,
          givenOn: BusinessDate(day),
        ),
      );

  group('the register', () {
    test('marks a day, a mark changed is the same row, and a day not yet '
        'come or before he joined is refused', () async {
      await mark('2026-09-03', {bilal: AttendanceMark.absent});
      await mark('2026-09-03', {bilal: AttendanceMark.present});
      expect(await count('attendance'), 1, reason: 'one row a man a day');
      final day = await reads.register(
        firm.firmId,
        const BusinessDate('2026-09-03'),
      );
      expect(day.single.employee.name, 'Bilal');
      expect(day.single.mark, AttendanceMark.present);
      expect(day.single.markedBy, 'Malik Sahib');
      final row = await db
          .customSelect('SELECT id, rev FROM attendance')
          .getSingle();
      expect(row.read<String>('id'), 'att-$bilal-2026-09-03');
      expect(row.read<int>('rev'), 2);

      await expectLater(
        writer.mark(on('2026-09-03'), const BusinessDate('2026-09-04'), {
          bilal: AttendanceMark.present,
        }),
        throwsA(isA<StaffRefused>()),
        reason: 'tomorrow is not marked today',
      );
      await expectLater(
        mark('2026-07-31', {bilal: AttendanceMark.present}),
        throwsA(isA<StaffRefused>()),
        reason: 'he had not joined',
      );
      expect(await count('attendance'), 1);
    });
  });

  group('a month of wages', () {
    test('a monthly salary is worked out from the register and paid: wages '
        'in the profit and loss, the drawer down, the books balance', () async {
      await markSeptember();
      final slipId = await pay();
      final slip = (await reads.slip(firm.firmId, slipId))!;
      expect(slip.slipNo, startsWith('SAL-2627-'));
      // 30-day rule, the shop's default: 30 - 2 - 1/2 days of 30.
      expect(slip.dayRule, DayRule.thirtyDay);
      expect(slip.paidDaysText, '27½');
      expect(slip.figures.basePay, Money.rupees(27500));
      expect(slip.figures.net, Money.rupees(27500));
      expect(slip.tally.absent, 2);
      expect(slip.tally.late, 1);
      expect(slip.paymentAccountName, isNotNull);

      expect(await balance('salaries'), Money.rupees(27500));
      expect(await balance('cash_in_hand'), -Money.rupees(27500));
      expect(await db.findLedgerImbalances(), isEmpty);
      final pl = await reports.run(
        ReportKind.profitAndLoss,
        firmId: firm.firmId,
        period: ReportPeriod.monthOf(const BusinessDate('2026-10-01')),
        today: const BusinessDate('2026-10-01'),
      );
      expect(
        pl.rows
            .where((r) => r.cells.first == 'Salaries and Wages')
            .single
            .cells[1],
        Money.rupees(27500),
      );
      final tags = await db
          .customSelect('SELECT DISTINCT cost_centre FROM journal_lines')
          .get();
      expect([for (final t in tags) t.data['cost_centre']], ['staff:$bilal']);
    });

    test(
      'under the calendar rule the same month is paid by its own days',
      () async {
        await writer.setRules(
          on('2026-09-01'),
          const StaffRules(dayRule: DayRule.calendar),
        );
        await markSeptember();
        final slip = (await reads.slip(firm.firmId, await pay()))!;
        expect(slip.dayRule, DayRule.calendar);
        expect(slip.basisDays, 30, reason: 'September has thirty days');
        // Unpaid leave cuts as absence does.
        await mark('2026-10-05', {bilal: AttendanceMark.unpaidLeave});
        final october = (await reads.slip(
          firm.firmId,
          await pay(month: SalaryMonth(2026, 10), paidOn: '2026-10-31'),
        ))!;
        expect(october.basisDays, 31);
        // 30,000 x 60 / 62 = 29,032.26.
        expect(october.figures.basePay, Money.rupees(29032));
      },
    );

    test('a daily wage pays the days he came, half days half', () async {
      final saleem = await writer.addEmployee(
        on('2026-09-01'),
        EmployeeDraft(
          name: 'Saleem',
          kaam: EmployeeKaam.helper,
          basis: PayBasis.daily,
          rate: Money.rupees(1200),
          joinedOn: const BusinessDate('2026-09-01'),
        ),
      );
      for (var d = 1; d <= 20; d++) {
        final day = '2026-09-${d.toString().padLeft(2, '0')}';
        await mark(day, {
          saleem: d == 4 || d == 5
              ? AttendanceMark.halfDay
              : d == 6
              ? AttendanceMark.absent
              : AttendanceMark.present,
        });
      }
      final slip = (await reads.slip(
        firm.firmId,
        await pay(employee: saleem),
      ))!;
      expect(slip.basis, PayBasis.daily);
      expect(slip.paidDaysText, '18');
      expect(slip.figures.basePay, Money.rupees(21600));
      expect(slip.tally.unmarked, 10, reason: 'and not paid');
      expect(await db.findLedgerImbalances(), isEmpty);
    });

    test(
      'a month paid already is refused until its slip is cancelled',
      () async {
        final first = await pay();
        await expectLater(pay(), throwsA(isA<StaffRefused>()));
        await writer.cancelSalary(on('2026-10-02'), first, reason: 'Twice');
        await pay(paidOn: '2026-10-02');
        expect(await count('salary_slips'), 2);
      },
    );
  });

  group('advances', () {
    test('an advance is an asset until it comes back off his wages, and the '
        'staff book and the balance sheet agree', () async {
      await advance(2000);
      await advance(3000, day: '2026-09-20');
      expect(await balance('staff_advances'), Money.rupees(5000));
      expect(await balance('cash_in_hand'), -Money.rupees(5000));
      expect(await reads.advanceOwed(firm.firmId, bilal), Money.rupees(5000));

      final slip = (await reads.slip(firm.firmId, await pay(recover: 4000)))!;
      expect(slip.figures.recovered, Money.rupees(4000));
      expect(slip.figures.net, Money.rupees(26000));
      expect(await balance('staff_advances'), Money.rupees(1000));
      expect(await balance('salaries'), Money.rupees(30000));
      expect(await reads.advanceOwed(firm.firmId, bilal), Money.rupees(1000));
      // Paid 5,000 out as advances and 26,000 as wages.
      expect(await balance('cash_in_hand'), -Money.rupees(31000));
      expect(await db.findLedgerImbalances(), isEmpty);

      final lines = await reads.advanceLines(firm.firmId, bilal);
      expect(
        [for (final l in lines) l.kind],
        [
          AdvanceLineKind.given,
          AdvanceLineKind.given,
          AdvanceLineKind.recovered,
        ],
      );
      expect(lines.last.owedAfter, Money.rupees(1000));
      expect(lines.last.slipId, slip.id);

      final bs = await reports.run(
        ReportKind.balanceSheet,
        firmId: firm.firmId,
        period: ReportPeriod.day(const BusinessDate('2026-10-01')),
        today: const BusinessDate('2026-10-01'),
      );
      expect(
        bs.rows
            .where((r) => r.cells.first == 'Staff Advances')
            .single
            .cells
            .last,
        Money.rupees(1000),
      );
    });

    test('more of an advance than he owes is refused, and nothing is '
        'written', () async {
      await advance(2000);
      final entries = await count('journal_entries');
      await expectLater(
        pay(recover: 2500),
        throwsA(
          isA<StaffRefused>().having(
            (e) => e.reason,
            'reason',
            contains('owes Rs 2,000.00'),
          ),
        ),
      );
      expect(await count('journal_entries'), entries);
      expect(await count('salary_slips'), 0);
    });

    test('an advance cancelled is reversed, and one already taken back off '
        'his wages is refused', () async {
      final first = await advance(2000);
      await advance(1000, day: '2026-09-14');
      final firstId = (await reads.advanceLines(
        firm.firmId,
        bilal,
      )).firstWhere((l) => l.entryNo == first).entryId;
      await pay(recover: 3000);
      await expectLater(
        writer.cancelAdvance(
          on('2026-10-02'),
          employeeId: bilal,
          entryId: firstId,
          reason: 'Typed twice',
        ),
        throwsA(isA<StaffRefused>()),
        reason: 'it has come back off his wages already',
      );
      final slip = (await reads.slips(firm.firmId, employeeId: bilal)).single;
      await writer.cancelSalary(on('2026-10-02'), slip.id, reason: 'Wrong');
      await writer.cancelAdvance(
        on('2026-10-02'),
        employeeId: bilal,
        entryId: firstId,
        reason: 'Typed twice',
      );
      expect(await reads.advanceOwed(firm.firmId, bilal), Money.rupees(1000));
      final kinds = [
        for (final l in await reads.advanceLines(firm.firmId, bilal)) l.kind,
      ];
      expect(kinds, [
        AdvanceLineKind.given,
        AdvanceLineKind.given,
        AdvanceLineKind.recovered,
        AdvanceLineKind.recoveryCancelled,
        AdvanceLineKind.givenCancelled,
      ]);
      expect(await db.findLedgerImbalances(), isEmpty);
    });

    test(
      'a man who still owes an advance cannot be put in the recycle bin',
      () async {
        await advance(2000);
        await expectLater(
          writer.setHidden(on('2026-09-15'), bilal, hidden: true),
          throwsA(isA<StaffRefused>()),
        );
        await pay(recover: 2000);
        await writer.setHidden(on('2026-10-01'), bilal, hidden: true);
        expect(await reads.employees(firm.firmId), isEmpty);
        expect(
          (await reads.employees(firm.firmId, hidden: true)).single.id,
          bilal,
        );
        final audit = await db
            .customSelect(
              'SELECT entity_table FROM audit_log WHERE action_code = '
              "'EMPLOYEE_HIDDEN'",
            )
            .getSingle();
        expect(
          audit.read<String>('entity_table'),
          hidingActions['EMPLOYEE_HIDDEN'],
        );
      },
    );

    test('a shop set up before the staff book gets Staff Advances when its '
        'first advance is given', () async {
      await db.customStatement(
        "DELETE FROM accounts WHERE system_key = 'staff_advances'",
      );
      await advance(1500);
      final added = await db
          .customSelect(
            'SELECT a.code, p.code AS parent FROM accounts a '
            'JOIN accounts p ON p.id = a.parent_id '
            "WHERE a.system_key = 'staff_advances'",
          )
          .getSingle();
      expect(added.read<String>('code'), '1160');
      expect(added.read<String>('parent'), '1000');
      expect(await balance('staff_advances'), Money.rupees(1500));
    });
  });

  group('putting a slip right', () {
    test('a cancelled salary is reversed by the opposite entry, and what it '
        'took off his advance is owed again', () async {
      await advance(2000);
      final slipId = await pay(recover: 2000);
      final reversal = await writer.cancelSalary(
        on('2026-10-03'),
        slipId,
        reason: 'Paid the wrong man',
      );
      expect(reversal, startsWith('JV-'));
      final slip = (await reads.slip(firm.firmId, slipId))!;
      expect(slip.cancelled, isTrue);
      expect(slip.voidReason, 'Paid the wrong man');
      expect(await balance('salaries'), Money.zero);
      expect(await balance('staff_advances'), Money.rupees(2000));
      expect(await balance('cash_in_hand'), -Money.rupees(2000));
      final entry = await db
          .customSelect(
            'SELECT entry_date_local, reverses_entry_id FROM journal_entries '
            'WHERE entry_no = ?',
            variables: [Variable<String>(reversal)],
          )
          .getSingle();
      expect(entry.read<String>('entry_date_local'), '2026-10-03');
      expect(entry.read<String>('reverses_entry_id'), slip.entryId);
      expect(await db.findLedgerImbalances(), isEmpty);
      await expectLater(
        writer.cancelSalary(on('2026-10-03'), slipId, reason: 'again'),
        throwsA(isA<StaffRefused>()),
      );
    });

    test('a slip corrected is cancelled and paid again in one act, the new '
        'slip pointing at the old', () async {
      final wrong = await pay();
      final right = await writer.correctSalary(
        on('2026-10-02'),
        wrong,
        SalaryDraft(
          employeeId: bilal,
          month: september,
          paidOn: const BusinessDate('2026-10-02'),
          lines: [
            SalaryLine(
              kind: SalaryLineKind.bonus,
              label: 'Rabi ul Awal bonus',
              amount: Money.rupees(2000),
            ),
          ],
          paymentAccountId: cash,
        ),
        reason: 'Forgot the bonus',
      );
      final old = (await reads.slip(firm.firmId, wrong))!;
      final now = (await reads.slip(firm.firmId, right))!;
      expect(old.cancelled, isTrue);
      expect(old.replacedBySlipNo, now.slipNo);
      expect(now.replacesSlipId, wrong);
      expect(now.figures.net, Money.rupees(32000));
      expect(now.lines.single.label, 'Rabi ul Awal bonus');
      expect(await balance('salaries'), Money.rupees(32000));
      final corrected = await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM audit_log WHERE action_code = '
            "'SALARY_CORRECTED'",
          )
          .getSingle();
      expect(corrected.read<int>('n'), 1);
      expect(await db.findLedgerImbalances(), isEmpty);
    });
  });

  group("the owner's locks", () {
    Future<void> setting(String key, String value) =>
        runner.run(on('2026-10-01'), (tx) async {
          await tx.insert('settings', {
            'setting_key': key,
            'setting_value': value,
          });
        });

    test('closed books refuse a mark, a salary or a cancel dated inside '
        'them', () async {
      await mark('2026-09-03', {bilal: AttendanceMark.absent});
      final slipId = await pay(paidOn: '2026-09-30');
      await setting(booksClosedThroughSetting, '2026-09-30');
      await expectLater(
        mark('2026-09-03', {bilal: AttendanceMark.present}),
        throwsA(isA<ApprovalNeeded>()),
        reason: 'a closed day register stays as it was closed',
      );
      await expectLater(
        mark('2026-09-04', {bilal: AttendanceMark.present}),
        throwsA(isA<ApprovalNeeded>()),
      );
      await expectLater(
        writer.cancelSalary(on('2026-10-02'), slipId, reason: 'Wrong'),
        throwsA(isA<ApprovalNeeded>()),
      );
      // Today's register is open.
      await mark('2026-10-01', {bilal: AttendanceMark.present});
      final marked = await reads.marksOf(
        firm.firmId,
        bilal,
        september.first,
        september.last,
      );
      expect(marked, {'2026-09-03': AttendanceMark.absent});
    });

    test('Data Lock asks for a PIN before a salary or an advance is '
        'cancelled', () async {
      final entry = await advance(2000);
      final slipId = await pay();
      await setting(dataLockSetting, '1');
      await expectLater(
        writer.cancelSalary(on('2026-10-02'), slipId, reason: 'Wrong'),
        throwsA(
          isA<ApprovalNeeded>().having(
            (e) => e.kind,
            'kind',
            ApprovalKind.dataLock,
          ),
        ),
      );
      final id = (await reads.advanceLines(
        firm.firmId,
        bilal,
      )).firstWhere((l) => l.entryNo == entry).entryId;
      await expectLater(
        writer.cancelAdvance(
          on('2026-10-02'),
          employeeId: bilal,
          entryId: id,
          reason: 'Wrong',
        ),
        throwsA(isA<ApprovalNeeded>()),
      );
      expect((await reads.slip(firm.firmId, slipId))!.cancelled, isFalse);
    });
  });

  group('the reports', () {
    test('the attendance summary, the salary register and the advances '
        'outstanding read the staff book', () async {
      await markSeptember();
      await advance(5000);
      await pay(recover: 3000);
      final period = ReportPeriod(september.first, september.last);
      const today = BusinessDate('2026-10-01');

      final attendance = await reports.run(
        ReportKind.staffAttendance,
        firmId: firm.firmId,
        period: period,
        today: today,
      );
      expect(attendance.rows.first.cells, [
        'Bilal',
        'Salesman',
        0,
        1,
        1,
        1,
        0,
        2,
        25,
      ]);

      final register = await reports.run(
        ReportKind.salaryRegister,
        firmId: firm.firmId,
        period: period,
        today: today,
      );
      final row = register.rows.first.cells;
      expect(row[0], 'Bilal');
      expect(row[1], '2026-09');
      expect(row[5], Money.rupees(27500));
      expect(row[9], Money.rupees(3000));
      expect(row[10], Money.rupees(24500));

      final owed = await reports.run(
        ReportKind.staffAdvances,
        firmId: firm.firmId,
        period: ReportPeriod.day(today),
        today: today,
      );
      expect(owed.rows.first.cells, [
        'Bilal',
        'Salesman',
        Money.rupees(5000),
        Money.rupees(3000),
        Money.rupees(2000),
      ]);
    });
  });
}
