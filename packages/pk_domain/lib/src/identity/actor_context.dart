import '../time/clock.dart';

/// Who is writing, from where, on whose behalf, and at what instant.
///
/// This is a REQUIRED parameter of every mutation in the application, from the
/// first line of code in M0 — long before there are multiple users to
/// distinguish. That is the entire point: adding an actor to a write path
/// later means auditing three hundred call sites and inventing a plausible
/// author for every row already in every user's database. M9 only has to
/// populate [userId] from a session that by then exists.
final class ActorContext {
  ActorContext({
    required this.firmId,
    required this.userId,
    required this.deviceId,
    required this.startedAtUtc,
    Duration timeZoneOffset = pakistanStandardTime,
  })  : _offset = timeZoneOffset,
        assert(firmId != '', 'firmId must not be empty'),
        assert(userId != '', 'userId must not be empty'),
        assert(deviceId != '', 'deviceId must not be empty');

  /// Builds a context stamped with the current instant.
  factory ActorContext.now({
    required String firmId,
    required String userId,
    required String deviceId,
    required Clock clock,
    Duration timeZoneOffset = pakistanStandardTime,
  }) =>
      ActorContext(
        firmId: firmId,
        userId: userId,
        deviceId: deviceId,
        startedAtUtc: clock.nowUtc(),
        timeZoneOffset: timeZoneOffset,
      );

  final String firmId;
  final String userId;
  final String deviceId;

  /// The instant the operation began.
  ///
  /// Every row a single transaction writes shares this timestamp. A sale's
  /// invoice, its lines, its payment and its journal entry must not carry
  /// three different `created_at_utc` values just because the write took
  /// eleven milliseconds — reports group on it, and a document that appears to
  /// predate its own lines is a bug that only shows up under load.
  final DateTime startedAtUtc;

  final Duration _offset;

  /// The shopkeeper's calendar day for [startedAtUtc].
  BusinessDate get businessDate =>
      BusinessDate.fromUtc(startedAtUtc, _offset);

  int get epochMillis => startedAtUtc.millisecondsSinceEpoch;

  /// The same actor at a later instant, for a second operation in the same
  /// session.
  ActorContext at(DateTime instant) => ActorContext(
        firmId: firmId,
        userId: userId,
        deviceId: deviceId,
        startedAtUtc: instant,
        timeZoneOffset: _offset,
      );

  @override
  String toString() =>
      'ActorContext(firm: $firmId, user: $userId, device: $deviceId, '
      'at: ${startedAtUtc.toIso8601String()})';
}
