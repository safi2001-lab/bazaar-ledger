import '../identity/actor_context.dart';
import 'roles.dart';

/// Somebody who uses the app: the owner, or staff the owner added.
final class StaffMember {
  const StaffMember({
    required this.id,
    required this.name,
    required this.role,
    required this.hasPin,
    required this.isActive,
    this.lastSignInUtcMillis,
  });

  final String id;
  final String name;
  final Role role;
  final bool hasPin;

  /// False once the owner has let them go. Their rows stay theirs.
  final bool isActive;
  final int? lastSignInUtcMillis;
}

/// A PIN as stored: the hash and its salt.
typedef StoredPin = ({String hash, String salt});

/// Where staff are kept. Every write goes through the one write path and
/// leaves an audit row naming who did it.
abstract interface class StaffStore {
  /// Everybody, the owner first, then by name.
  Future<List<StaffMember>> staff(String firmId);

  Future<StaffMember?> member(String firmId, String userId);

  /// The stored PIN, or null when they have none.
  Future<StoredPin?> pinOf(String firmId, String userId);

  /// Adds somebody. Returns their id.
  Future<String> add(
    ActorContext actor, {
    required String name,
    required Role role,
    required StoredPin pin,
  });

  Future<void> setPin(ActorContext actor, String userId, StoredPin pin);

  Future<void> setRole(ActorContext actor, String userId, Role role);

  Future<void> setActive(
    ActorContext actor,
    String userId, {
    required bool active,
  });

  /// Stamps the sign-in on the user and in the audit log.
  Future<void> recordSignIn(ActorContext actor);
}
