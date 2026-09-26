import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';
import 'tx_runner.dart';

/// The drift implementation of [StaffStore].
final class DriftStaffStore implements StaffStore {
  const DriftStaffStore(this._db, this._runner);

  final AppDatabase _db;
  final TxRunner Function() _runner;

  static const _select = '''
    SELECT id, name, role, pin_hash IS NOT NULL AS has_pin, is_active,
           last_login_at_utc
    FROM users
  ''';

  static StaffMember _member(QueryRow r) => StaffMember(
    id: r.read<String>('id'),
    name: r.read<String>('name'),
    // A role this build does not know is read as the least it could be,
    // never as more.
    role: Role.parse(r.read<String>('role')) ?? Role.cashier,
    hasPin: r.read<int>('has_pin') == 1,
    isActive: r.read<int>('is_active') == 1,
    lastSignInUtcMillis: r.readNullable<int>('last_login_at_utc'),
  );

  @override
  Future<List<StaffMember>> staff(String firmId) async {
    final rows = await _db
        .customSelect(
          '$_select WHERE firm_id = ? AND deleted_at_utc IS NULL '
          "ORDER BY role <> 'owner', name COLLATE NOCASE",
          variables: [Variable<String>(firmId)],
          readsFrom: {_db.users},
        )
        .get();
    return [for (final r in rows) _member(r)];
  }

  @override
  Future<StaffMember?> member(String firmId, String userId) async {
    final row = await _db
        .customSelect(
          '$_select WHERE firm_id = ? AND id = ? AND deleted_at_utc IS NULL',
          variables: [Variable<String>(firmId), Variable<String>(userId)],
          readsFrom: {_db.users},
        )
        .getSingleOrNull();
    return row == null ? null : _member(row);
  }

  @override
  Future<StoredPin?> pinOf(String firmId, String userId) async {
    final row = await _db
        .customSelect(
          'SELECT pin_hash, pin_salt FROM users '
          'WHERE firm_id = ? AND id = ? AND deleted_at_utc IS NULL',
          variables: [Variable<String>(firmId), Variable<String>(userId)],
          readsFrom: {_db.users},
        )
        .getSingleOrNull();
    final hash = row?.readNullable<String>('pin_hash');
    final salt = row?.readNullable<String>('pin_salt');
    if (hash == null || salt == null) return null;
    return (hash: hash, salt: salt);
  }

  /// The columns a role decides. Kept on the row, where M0 put them for
  /// ActorContext to read, and rewritten whenever the role changes.
  static Map<String, Object?> _roleColumns(Role role) => {
    'role': role.name,
    'can_see_purchase_price': role.can(Permission.seeCosts) ? 1 : 0,
    'can_see_margin': role.can(Permission.seeCosts) ? 1 : 0,
    'max_discount_bp': role.maxDiscountBp,
  };

  @override
  Future<String> add(
    ActorContext actor, {
    required String name,
    required Role role,
    required StoredPin pin,
  }) => _runner().run(actor, (tx) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (role == Role.owner) {
      // One owner. A second would be a second person who can remove the
      // first, and a shop has one proprietor.
      throw const PermissionDenied(
        Permission.manageUsers,
        'A shop has one owner. Add them as a manager.',
      );
    }
    final id = await tx.insert('users', {
      'name': trimmed,
      ..._roleColumns(role),
      'pin_hash': pin.hash,
      'pin_salt': pin.salt,
    });
    tx.audit(
      action: 'USER_ADDED',
      entityTable: 'users',
      entityId: id,
      summary: '$trimmed added as ${role.name}',
    );
    return id;
  });

  @override
  Future<void> setPin(ActorContext actor, String userId, StoredPin pin) =>
      _runner().run(actor, (tx) async {
        final name = await _nameOf(tx, userId);
        await tx.update('users', userId, {
          'pin_hash': pin.hash,
          'pin_salt': pin.salt,
        });
        tx.audit(
          action: 'USER_PIN_SET',
          entityTable: 'users',
          entityId: userId,
          summary: 'PIN set for $name',
        );
      });

  @override
  Future<void> setRole(ActorContext actor, String userId, Role role) =>
      _runner().run(actor, (tx) async {
        final row = await tx.selectOne(
          'SELECT name, role FROM users WHERE id = ? AND firm_id = ?',
          [userId, actor.firmId],
        );
        if (row == null) throw StateError('No such user in this shop.');
        final was = row.read<String>('role');
        if (was == 'owner' || role == Role.owner) {
          throw const PermissionDenied(
            Permission.manageUsers,
            "The owner's role cannot be given or taken away.",
          );
        }
        await tx.update('users', userId, _roleColumns(role));
        tx.audit(
          action: 'USER_ROLE_CHANGED',
          entityTable: 'users',
          entityId: userId,
          summary:
              '${row.read<String>('name')} changed from $was to '
              '${role.name}',
          before: {'role': was},
          after: {'role': role.name},
        );
      });

  @override
  Future<void> setActive(
    ActorContext actor,
    String userId, {
    required bool active,
  }) => _runner().run(actor, (tx) async {
    final row = await tx.selectOne(
      'SELECT name, role FROM users WHERE id = ? AND firm_id = ?',
      [userId, actor.firmId],
    );
    if (row == null) throw StateError('No such user in this shop.');
    if (row.read<String>('role') == 'owner') {
      throw const PermissionDenied(
        Permission.manageUsers,
        'The owner cannot be switched off.',
      );
    }
    await tx.update('users', userId, {'is_active': active ? 1 : 0});
    final name = row.read<String>('name');
    tx.audit(
      action: active ? 'USER_REACTIVATED' : 'USER_DEACTIVATED',
      entityTable: 'users',
      entityId: userId,
      summary: active
          ? '$name can sign in again'
          : '$name can no longer sign in',
    );
  });

  @override
  Future<void> recordSignIn(ActorContext actor) =>
      _runner().run(actor, (tx) async {
        final name = await _nameOf(tx, actor.userId);
        await tx.update('users', actor.userId, {
          'last_login_at_utc': actor.epochMillis,
        });
        tx.audit(
          action: 'USER_SIGNED_IN',
          entityTable: 'users',
          entityId: actor.userId,
          summary: '$name signed in',
        );
      });

  static Future<String> _nameOf(Tx tx, String userId) async {
    final row = await tx.selectOne(
      'SELECT name FROM users WHERE id = ? AND firm_id = ?',
      [userId, tx.actor.firmId],
    );
    if (row == null) throw StateError('No such user in this shop.');
    return row.read<String>('name');
  }
}
