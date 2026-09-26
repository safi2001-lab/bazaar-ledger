import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// Staff against a real database: added by the owner, their role on their
/// row, and every change in the audit log with the owner's name on it.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late ActorContext owner;
  late DriftStaffStore staff;

  const pin = (hash: 'aGFzaA==', salt: 'c2FsdA==');

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 9, 26, 9, 15));
    db = await openTestDatabase();
    final ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    owner = firm.actorAt(clock.nowUtc());
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    final runner = TxRunner(database: db, ids: ids, hlc: hlc);
    staff = DriftStaffStore(db, () => runner);
  });

  tearDown(() async => db.close());

  Future<List<Map<String, Object?>>> rows(String sql) async => [
    for (final r in await db.customSelect(sql).get()) r.data,
  ];

  test('a cashier is added with the role on their row', () async {
    final id = await staff.add(
      owner,
      name: 'Bilal',
      role: Role.cashier,
      pin: pin,
    );

    final row = (await rows(
      'SELECT role, pin_hash, can_see_purchase_price, max_discount_bp '
      "FROM users WHERE id = '$id'",
    )).single;
    expect(row['role'], 'cashier');
    expect(row['pin_hash'], pin.hash);
    expect(row['can_see_purchase_price'], 0);
    expect(row['max_discount_bp'], 500);
    final everyone = await staff.staff(firm.firmId);
    expect([for (final m in everyone) m.name], ['Malik Sahib', 'Bilal']);
    expect(everyone.last.hasPin, isTrue);
  });

  test('every change to staff is in the audit log under the owner', () async {
    final id = await staff.add(
      owner,
      name: 'Bilal',
      role: Role.cashier,
      pin: pin,
    );
    await staff.setRole(owner, id, Role.manager);
    await staff.setActive(owner, id, active: false);

    final audit = await rows(
      "SELECT action_code, created_by FROM audit_log WHERE entity_table = 'users' "
      'ORDER BY at_utc, rowid',
    );
    expect(
      [for (final a in audit) a['action_code']],
      ['USER_ADDED', 'USER_ROLE_CHANGED', 'USER_DEACTIVATED'],
    );
    expect(audit.every((a) => a['created_by'] == firm.ownerUserId), isTrue);
    final member = await staff.member(firm.firmId, id);
    expect(member!.role, Role.manager);
    expect(member.isActive, isFalse);
  });

  test('there is one owner, and nobody takes the role away', () async {
    await expectLater(
      staff.add(owner, name: 'Second', role: Role.owner, pin: pin),
      throwsA(isA<PermissionDenied>()),
    );
    await expectLater(
      staff.setRole(owner, firm.ownerUserId, Role.cashier),
      throwsA(isA<PermissionDenied>()),
    );
    await expectLater(
      staff.setActive(owner, firm.ownerUserId, active: false),
      throwsA(isA<PermissionDenied>()),
    );
  });

  test('a sign-in is stamped on the user and in the log', () async {
    final id = await staff.add(
      owner,
      name: 'Bilal',
      role: Role.cashier,
      pin: pin,
    );
    final bilal = ActorContext(
      firmId: firm.firmId,
      userId: id,
      deviceId: firm.deviceId,
      startedAtUtc: DateTime.utc(2026, 9, 26, 10),
    );
    await staff.recordSignIn(bilal);

    final member = await staff.member(firm.firmId, id);
    expect(member!.lastSignInUtcMillis, bilal.epochMillis);
    final log = await rows(
      "SELECT created_by, summary FROM audit_log WHERE action_code = 'USER_SIGNED_IN'",
    );
    expect(log.single['created_by'], id);
    expect(log.single['summary'], 'Bilal signed in');
  });
}
