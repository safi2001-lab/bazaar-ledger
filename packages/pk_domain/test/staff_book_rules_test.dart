import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// The staff book's pure rules (M65): a month's wages worked out from the
/// register under each rule, the checks on a slip and an advance, and the
/// entries both post.
void main() {
  final october = SalaryMonth(2026, 10);
  const today = BusinessDate('2026-11-02');

  Employee man({
    PayBasis basis = PayBasis.monthly,
    int rupees = 30000,
    String joined = '2025-01-01',
    String? left,
  }) => Employee(
    id: 'E1',
    name: 'Bilal',
    kaam: EmployeeKaam.helper,
    basis: basis,
    rate: Money.rupees(rupees),
    joinedOn: BusinessDate(joined),
    leftOn: left == null ? null : BusinessDate(left),
  );

  Map<String, AttendanceMark> marks(Map<int, AttendanceMark> byDay) => {
    for (final e in byDay.entries) october.everyDay[e.key - 1].value: e.value,
  };

  group('a month of a monthly salary', () {
    final register = marks({
      3: AttendanceMark.absent,
      4: AttendanceMark.absent,
      5: AttendanceMark.halfDay,
      6: AttendanceMark.paidLeave,
      7: AttendanceMark.late,
    });

    test('under the 30-day rule a day is a thirtieth, absences and half '
        'days cut, paid leave and late do not', () {
      final w = workWages(
        employee: man(),
        month: october,
        marks: register,
        rule: DayRule.thirtyDay,
        today: today,
      );
      expect(w.basisDays, 30);
      expect(w.tally.absent, 2);
      expect(w.tally.halfDay, 1);
      expect(w.tally.paidLeave, 1);
      expect(w.tally.late, 1);
      expect(w.tally.unmarked, 26, reason: 'counted as worked');
      expect(w.paidHalves, 55);
      expect(w.paidDaysText, '27½');
      // 30,000 x 55 / 60.
      expect(w.basePay, Money.rupees(27500));
    });

    test('under the calendar rule a day is the month own share, rounded to '
        'the rupee', () {
      final w = workWages(
        employee: man(),
        month: october,
        marks: register,
        rule: DayRule.calendar,
        today: today,
      );
      expect(w.basisDays, 31);
      expect(w.paidHalves, 57);
      // 30,000 x 57 / 62 = 27,580.65, paid as 27,581.
      expect(w.basePay, Money.rupees(27581));
    });

    test('a whole month with no day away is the whole salary, in February '
        'too', () {
      for (final rule in DayRule.values) {
        final w = workWages(
          employee: man(),
          month: SalaryMonth(2027, 2),
          marks: const {},
          rule: rule,
          today: const BusinessDate('2027-03-01'),
        );
        expect(w.basePay, Money.rupees(30000), reason: rule.code);
      }
    });

    test('unpaid leave is cut as an absence is', () {
      final w = workWages(
        employee: man(),
        month: october,
        marks: marks({10: AttendanceMark.unpaidLeave}),
        rule: DayRule.thirtyDay,
        today: today,
      );
      expect(w.paidHalves, 58);
      expect(w.basePay, Money.rupees(29000));
    });

    test('a man who joined in the middle of the month is paid for his days '
        'on the payroll', () {
      final w = workWages(
        employee: man(joined: '2026-10-16'),
        month: october,
        marks: marks({20: AttendanceMark.absent}),
        rule: DayRule.thirtyDay,
        today: today,
      );
      expect(w.tally.employedDays, 16);
      expect(w.tally.absent, 1);
      // 16 days less one: 30,000 x 30 / 60.
      expect(w.basePay, Money.rupees(15000));
    });

    test('a man who left in the middle is paid up to his last day', () {
      final w = workWages(
        employee: man(left: '2026-10-10'),
        month: october,
        marks: const {},
        rule: DayRule.calendar,
        today: today,
      );
      expect(w.tally.employedDays, 10);
      // 30,000 x 20 / 62 = 9,677.42.
      expect(w.basePay, Money.rupees(9677));
    });
  });

  group('a month of a daily wage', () {
    test('a day he came is a day wage, a half day half, and a day nobody '
        'marked is not paid', () {
      final register = <String, AttendanceMark>{};
      final days = october.everyDay;
      for (var i = 0; i < 20; i++) {
        register[days[i].value] = AttendanceMark.present;
      }
      register[days[20].value] = AttendanceMark.late;
      register[days[21].value] = AttendanceMark.late;
      register[days[22].value] = AttendanceMark.halfDay;
      register[days[23].value] = AttendanceMark.halfDay;
      register[days[24].value] = AttendanceMark.halfDay;
      register[days[25].value] = AttendanceMark.paidLeave;
      register[days[26].value] = AttendanceMark.absent;
      final w = workWages(
        employee: man(basis: PayBasis.daily, rupees: 1000),
        month: october,
        marks: register,
        rule: DayRule.thirtyDay,
        today: today,
      );
      expect(w.dayRule, isNull);
      expect(w.tally.unmarked, 4);
      // 20 present, 2 late, 1 paid leave: 23 days; 3 half days.
      expect(w.paidHalves, 49);
      expect(w.paidDaysText, '24½');
      expect(w.basePay, Money.rupees(24500));
    });
  });

  group('a slip', () {
    final w = workWages(
      employee: man(),
      month: october,
      marks: const {},
      rule: DayRule.thirtyDay,
      today: today,
    );

    SalaryFigures check({
      List<SalaryLine> lines = const [],
      int recover = 0,
      int owed = 0,
      SalaryMonth? month,
      String? account = 'CASH',
    }) => checkSalary(
      employee: man(),
      working: w,
      draft: SalaryDraft(
        employeeId: 'E1',
        month: month ?? october,
        paidOn: today,
        lines: lines,
        advanceRecovered: Money.rupees(recover),
        paymentAccountId: account,
      ),
      advanceOwed: Money.rupees(owed),
      today: today,
    );

    test('adds bonus and overtime, takes cuts and the advance, and its '
        'entry balances', () {
      final f = check(
        lines: [
          SalaryLine(
            kind: SalaryLineKind.bonus,
            label: 'Eid bonus',
            amount: Money.rupees(5000),
          ),
          SalaryLine(
            kind: SalaryLineKind.overtime,
            label: 'Sunday',
            amount: Money.rupees(1000),
          ),
          SalaryLine(
            kind: SalaryLineKind.deduction,
            label: 'Broken glass',
            amount: Money.rupees(500),
          ),
        ],
        recover: 4000,
        owed: 6000,
      );
      expect(f.gross, Money.rupees(36000));
      expect(f.earned, Money.rupees(35500));
      expect(f.net, Money.rupees(31500));
      final entry = salaryEntry(
        figures: f,
        employeeName: 'Bilal',
        month: october,
        paidOn: today,
        entryNo: 'JV-2627-00007',
        recordedAtUtcMillis: 0,
        salariesAccountId: 'WAGES',
        advancesAccountId: 'ADV',
        moneyAccountId: 'CASH',
      );
      expect(entry.totalDebit, entry.totalCredit);
      expect(
        Money.sum([for (final l in entry.lines) l.debit]),
        Money.sum([for (final l in entry.lines) l.credit]),
      );
      expect(entry.lines.first.accountSystemKey, '#WAGES');
      expect(entry.lines.first.debit, Money.rupees(35500));
      expect(entry.lines[1].credit, Money.rupees(4000));
      expect(entry.lines[2].credit, Money.rupees(31500));
    });

    test('no more of an advance comes back than he owes, or than the month '
        'earned', () {
      expect(
        () => check(recover: 7000, owed: 6000),
        throwsA(
          isA<StaffRefused>().having(
            (e) => e.reason,
            'reason',
            contains('owes Rs 6,000.00'),
          ),
        ),
      );
      expect(
        () => check(recover: 40000, owed: 50000),
        throwsA(isA<StaffRefused>()),
      );
      // The whole month against his advance needs no drawer.
      final all = check(recover: 30000, owed: 50000, account: null);
      expect(all.net, Money.zero);
    });

    test('a month not yet come, and cuts past the gross, are refused', () {
      expect(
        () => check(month: SalaryMonth(2026, 12)),
        throwsA(isA<StaffRefused>()),
      );
      expect(
        () => check(
          lines: [
            SalaryLine(
              kind: SalaryLineKind.deduction,
              label: 'Theft',
              amount: Money.rupees(40000),
            ),
          ],
        ),
        throwsA(isA<StaffRefused>()),
      );
    });
  });

  group('an employee', () {
    test('a CNIC is optional and kept as its thirteen digits; a bad one, a '
        'blank name or a day not yet come is refused', () {
      EmployeeDraft draft({
        String name = 'Bilal',
        String? cnic,
        String joined = '2026-10-01',
      }) => EmployeeDraft(
        name: name,
        basis: PayBasis.monthly,
        rate: Money.rupees(25000),
        joinedOn: BusinessDate(joined),
        cnic: cnic,
      );
      checkEmployeeDraft(draft(), today: today);
      final kept = draft(cnic: '35202-1234567-1');
      checkEmployeeDraft(kept, today: today);
      expect(kept.cnicKept, '3520212345671');
      expect(draft(cnic: '  ').cnicKept, isNull);
      expect(
        () => checkEmployeeDraft(draft(cnic: '35202-123'), today: today),
        throwsA(isA<StaffRefused>()),
      );
      expect(
        () => checkEmployeeDraft(draft(name: ' '), today: today),
        throwsA(isA<StaffRefused>()),
      );
      expect(
        () => checkEmployeeDraft(draft(joined: '2026-11-03'), today: today),
        throwsA(isA<StaffRefused>()),
      );
    });

    test('an advance is Dr Staff Advances, Cr the drawer, and is refused '
        'before he joined', () {
      final draft = AdvanceDraft(
        employeeId: 'E1',
        amount: Money.rupees(2000),
        paymentAccountId: 'CASH',
        givenOn: const BusinessDate('2026-10-12'),
      );
      checkAdvance(draft, employee: man(), today: today);
      final entry = advanceEntry(
        draft: draft,
        employeeName: 'Bilal',
        entryNo: 'JV-2627-00003',
        recordedAtUtcMillis: 0,
        advancesAccountId: 'ADV',
        moneyAccountId: 'CASH',
      );
      expect(entry.lines.first.accountSystemKey, '#ADV');
      expect(entry.lines.first.debit, Money.rupees(2000));
      expect(entry.lines.last.credit, Money.rupees(2000));
      expect(
        () => checkAdvance(
          draft,
          employee: man(joined: '2026-10-20'),
          today: today,
        ),
        throwsA(isA<StaffRefused>()),
      );
    });
  });
}
