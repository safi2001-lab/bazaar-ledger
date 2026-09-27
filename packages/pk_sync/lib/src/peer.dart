/// One entry from a device's outbox, as it travels.
///
/// Opaque here on purpose: the columns are the `change_log` row, and only the
/// store that wrote them knows how to turn one back into a row. What this
/// package needs from a change is where it came from and where it sits in
/// that device's sequence.
extension type const SyncChange(Map<String, Object?> row) {
  String get originDeviceId => row['origin_device_id']! as String;
  int get seq => row['seq']! as int;
}

/// How far a peer has got with each device's outbox: the highest sequence
/// number it holds from each. A device missing from the map has sent nothing
/// this peer has seen.
typedef VersionVector = Map<String, int>;

/// What applying a batch did.
final class ApplyResult {
  const ApplyResult({
    required this.applied,
    required this.skipped,
    required this.conflicts,
  });

  static const none = ApplyResult(applied: 0, skipped: 0, conflicts: 0);

  /// Changes that moved a row.
  final int applied;

  /// Changes already held, or older than the row they would have changed.
  final int skipped;

  /// Changes that clashed with a row this peer already had under the same
  /// name or number, kept under a marked name for somebody to look at.
  final int conflicts;

  Map<String, Object?> toJson() => {
    'applied': applied,
    'skipped': skipped,
    'conflicts': conflicts,
  };

  static ApplyResult fromJson(Map<String, Object?> json) => ApplyResult(
    applied: json['applied']! as int,
    skipped: json['skipped']! as int,
    conflicts: json['conflicts']! as int,
  );
}

/// What a counter is told when the master lets it join.
final class JoinGrant {
  const JoinGrant({
    required this.firmId,
    required this.deviceId,
    required this.syncKey,
    required this.shopName,
  });

  final String firmId;

  /// The counter's own device row, made on the master.
  final String deviceId;

  /// The key every later request carries.
  final String syncKey;

  final String shopName;

  Map<String, Object?> toJson() => {
    'firm_id': firmId,
    'device_id': deviceId,
    'sync_key': syncKey,
    'shop_name': shopName,
  };

  static JoinGrant fromJson(Map<String, Object?> json) => JoinGrant(
    firmId: json['firm_id']! as String,
    deviceId: json['device_id']! as String,
    syncKey: json['sync_key']! as String,
    shopName: json['shop_name']! as String,
  );
}

/// One side of a sync: a device's books, seen as an outbox.
abstract interface class SyncPeer {
  /// The highest sequence held from each device.
  Future<VersionVector> vector();

  /// Every change held that [known] does not have, oldest first per device.
  Future<List<SyncChange>> changesSince(VersionVector known);

  /// Takes in changes from another device. Applying the same change twice
  /// changes nothing the second time.
  Future<ApplyResult> apply(List<SyncChange> changes);
}

/// Thrown when the other side refuses, in words a shopkeeper can act on.
final class SyncRefused implements Exception {
  const SyncRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}
