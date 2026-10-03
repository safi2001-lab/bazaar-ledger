import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// One clock for both phones, a millisecond on at every look.
final class _Ticking implements Clock {
  DateTime _t = DateTime.utc(2026, 10, 3, 5);

  @override
  DateTime nowUtc() => _t = _t.add(const Duration(milliseconds: 1));
}

/// The staff book through the services the app is built on (M65): who may
/// keep it, pay from it and mark its register; the register reaching the
/// other counter over a real socket, the later mark of a day winning on
/// both; and Data Lock standing in front of a cancelled salary.
void main() {
  late _Ticking clock;
  late AppServices shop;
  late String owner;
  late String cash;

  const today = BusinessDate('2026-10-03');

  setUp(() async {
    clock = _Ticking();
    shop = await openInMemoryServices(clock: clock);
    await shop.setUpShop(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Master',
    );
    owner = shop.currentUser!.id;
    final firmId = (await shop.queries.currentFirm())!.id;
    cash = (await shop.queries.paymentAccounts(
      firmId,
    )).firstWhere((a) => a.modeLabel == 'cash').id;
  });

  tearDown(() => shop.close());

  Future<String> hire(AppServices on, String name) => on.staffBook.add(
    EmployeeDraft(
      name: name,
      basis: PayBasis.monthly,
      rate: Money.rupees(25000),
      joinedOn: const BusinessDate('2026-09-01'),
    ),
  );

  test('the owner and a manager keep the staff book, the accountant pays '
      'from it, and a cashier marks the register only when the owner lets '
      'him, never seeing a rupee', () async {
    final bilal = await hire(shop, 'Bilal');
    await shop.setPin(owner, '1947');
    final manager = await shop.addStaff(
      name: 'Tariq',
      role: Role.manager,
      pin: '1111',
    );
    final munshi = await shop.addStaff(
      name: 'Munshi Aslam',
      role: Role.accountant,
      pin: '2222',
    );
    final boy = await shop.addStaff(
      name: 'Imran',
      role: Role.cashier,
      pin: '3333',
    );

    Future<void> as(String user, String pin) async {
      await shop.lock();
      expect(await shop.signIn(user, pin), isTrue);
    }

    // The accountant pays, and does not hire.
    await as(munshi, '2222');
    expect((await shop.staffBook.employees()).single.rate, Money.rupees(25000));
    await expectLater(hire(shop, 'Saleem'), throwsA(isA<PermissionDenied>()));
    await shop.staffBook.giveAdvance(
      AdvanceDraft(
        employeeId: bilal,
        amount: Money.rupees(1000),
        paymentAccountId: cash,
        givenOn: today,
      ),
    );
    final slip = await shop.staffBook.paySalary(
      SalaryDraft(
        employeeId: bilal,
        month: SalaryMonth(2026, 9),
        paidOn: today,
        advanceRecovered: Money.rupees(1000),
        paymentAccountId: cash,
      ),
    );
    expect((await shop.staffBook.slip(slip))!.figures.net, Money.rupees(24000));

    // The cashier: nothing, until the owner says so.
    await as(boy, '3333');
    expect(await shop.staffBook.mayMarkRegister(), isFalse);
    await expectLater(
      shop.staffBook.register(today),
      throwsA(isA<PermissionDenied>()),
    );
    await expectLater(
      shop.staffBook.employees(),
      throwsA(isA<PermissionDenied>()),
    );
    await expectLater(
      shop.staffBook.setRules(const StaffRules(cashierMarksAttendance: true)),
      throwsA(isA<PermissionDenied>()),
    );

    // The manager hires, and may not change the shop's rules.
    await as(manager, '1111');
    await hire(shop, 'Saleem');
    await expectLater(
      shop.staffBook.setRules(const StaffRules(cashierMarksAttendance: true)),
      throwsA(isA<PermissionDenied>()),
    );

    await as(owner, '1947');
    await shop.staffBook.setRules(
      const StaffRules(cashierMarksAttendance: true),
    );

    await as(boy, '3333');
    expect(await shop.staffBook.mayMarkRegister(), isTrue);
    final register = await shop.staffBook.register(today);
    expect([for (final l in register) l.employee.name], ['Bilal', 'Saleem']);
    expect(await shop.staffBook.markRestPresent(today), 2);
    expect(
      [for (final l in await shop.staffBook.register(today)) l.mark],
      [AttendanceMark.present, AttendanceMark.present],
    );
    // Names and marks; still never a rupee.
    await expectLater(
      shop.staffBook.employees(),
      throwsA(isA<PermissionDenied>()),
    );
    await expectLater(
      shop.staffBook.advanceOwed(bilal),
      throwsA(isA<PermissionDenied>()),
    );
    final health = await shop.checkHealth();
    expect(health.isHealthy, isTrue, reason: health.toString());
  });

  test('a mark made on one counter reaches the other over the shop wi-fi, '
      'and the later mark of a day wins on both', () async {
    final bilal = await hire(shop, 'Bilal');
    await shop.staffBook.mark(today, {bilal: AttendanceMark.present});

    final port = await shop.sync.startHosting(
      port: 0,
      address: InternetAddress.loopbackIPv4,
    );
    final counter = await openInMemoryServices(clock: clock);
    addTearDown(counter.close);
    await counter.sync.join(
      host: '127.0.0.1',
      port: port,
      code: shop.sync.openJoining(),
      label: 'Counter 2',
    );

    final arrived = await counter.staffBook.register(today);
    expect(arrived.single.employee.name, 'Bilal');
    expect(arrived.single.mark, AttendanceMark.present);

    // Apart, both phones change the same day: the master first, the counter
    // a moment later.
    await shop.staffBook.mark(today, {bilal: AttendanceMark.late});
    await counter.staffBook.mark(today, {bilal: AttendanceMark.halfDay});
    await counter.sync.syncNow();

    for (final phone in [shop, counter]) {
      final line = (await phone.staffBook.register(today)).single;
      expect(line.mark, AttendanceMark.halfDay, reason: 'the later mark');
    }
    expect(await shop.sync.conflicts(), 0, reason: 'one row, merged');
    expect(await counter.sync.conflicts(), 0);
    final health = await counter.checkHealth();
    expect(health.isHealthy, isTrue, reason: health.toString());
  });

  test('with Data Lock on, cancelling a salary asks for a PIN, and a man '
      'put in the recycle bin comes back with one tap', () async {
    final bilal = await hire(shop, 'Bilal');
    final slip = await shop.staffBook.paySalary(
      SalaryDraft(
        employeeId: bilal,
        month: SalaryMonth(2026, 9),
        paidOn: today,
        paymentAccountId: cash,
      ),
    );
    await shop.setPin(owner, '1947');
    await shop.audit.setDataLock(on: true);
    await expectLater(
      shop.staffBook.cancelSalary(slip, reason: 'Paid twice'),
      throwsA(isA<ApprovalNeeded>()),
    );
    final asked = <ApprovalAsk>[];
    shop.audit.prompt = (ask) async {
      asked.add(ask);
      return ApprovalAnswer(userId: owner, pin: '1947');
    };
    await shop.staffBook.cancelSalary(slip, reason: 'Paid twice');
    expect(asked, hasLength(1));
    expect((await shop.staffBook.slip(slip))!.cancelled, isTrue);

    await shop.staffBook.hide(bilal);
    expect(asked, hasLength(2), reason: 'hiding fills the bin');
    expect(await shop.staffBook.employees(), isEmpty);
    final marks = await shop.recycle.marks();
    expect(marks['employees/$bilal']?.by, 'Malik Sahib');
    await shop.staffBook.restore(bilal);
    expect(asked, hasLength(2), reason: 'bringing back asks nothing');
    expect((await shop.staffBook.employees()).single.name, 'Bilal');
  });
}
