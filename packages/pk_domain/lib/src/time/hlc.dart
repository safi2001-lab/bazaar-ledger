import 'clock.dart';

/// A hybrid logical clock timestamp.
///
/// Every row written by the application carries one. When two tills on the
/// same shop Wi-Fi both edit a party's credit limit while disconnected, the
/// HLC is what decides which edit is newer — and it decides the same way on
/// both devices, which a wall clock cannot promise. Two phones on a Pakistani
/// counter routinely disagree by minutes, and one of them is often wrong by
/// hours after a shopkeeper corrects the date by hand.
///
/// The wire format is fixed-width and ordered, so a plain string comparison is
/// a causal comparison and SQLite can index it:
///
///     0001998A2C40-0000-01J8ZQK7V9C3M4N5P6Q7R8S9TA
///     |            |    |
///     |            |    the device that minted it, breaking exact ties
///     |            counter, for events inside one millisecond
///     physical milliseconds, 48 bits of hex
extension type const Hlc(String value) implements Object {
  factory Hlc.of({
    required int millis,
    required int counter,
    required String deviceId,
  }) {
    if (millis < 0 || millis > _maxMillis) {
      throw ArgumentError.value(millis, 'millis', 'outside 48-bit range');
    }
    if (counter < 0 || counter > _maxCounter) {
      throw ArgumentError.value(counter, 'counter', 'outside 16-bit range');
    }
    final ms = millis.toRadixString(16).toUpperCase().padLeft(12, '0');
    final c = counter.toRadixString(16).toUpperCase().padLeft(4, '0');
    return Hlc('$ms-$c-$deviceId');
  }

  static const int _maxMillis = 0xFFFFFFFFFFFF;
  static const int _maxCounter = 0xFFFF;

  /// The earliest possible timestamp, used to seed a device that has never
  /// written anything.
  static const Hlc zero = Hlc('000000000000-0000-');

  static Hlc? tryParse(String input) {
    final parts = input.split('-');
    if (parts.length < 3) return null;
    if (parts[0].length != 12 || parts[1].length != 4) return null;
    if (int.tryParse(parts[0], radix: 16) == null) return null;
    if (int.tryParse(parts[1], radix: 16) == null) return null;
    return Hlc(input);
  }

  int get millis => int.parse(value.substring(0, 12), radix: 16);
  int get counter => int.parse(value.substring(13, 17), radix: 16);
  String get deviceId => value.substring(18);

  DateTime get physicalTime =>
      DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);

  bool operator <(Hlc other) => value.compareTo(other.value) < 0;
  bool operator >(Hlc other) => value.compareTo(other.value) > 0;
  bool operator <=(Hlc other) => value.compareTo(other.value) <= 0;
  bool operator >=(Hlc other) => value.compareTo(other.value) >= 0;
}

/// Issues [Hlc] timestamps for this device, and merges timestamps that arrive
/// from a peer.
///
/// Recovered on startup from the highest HLC this device ever wrote — which
/// the outbox already records, so there is no separate counter to keep in step
/// and nothing extra to lose in a crash.
final class HlcClock {
  HlcClock({
    required this.deviceId,
    required this.clock,
    Hlc? lastSeen,
    this.maxDrift = const Duration(hours: 1),
  })  : _millis = lastSeen == null || lastSeen == Hlc.zero
            ? 0
            : lastSeen.millis,
        _counter =
            lastSeen == null || lastSeen == Hlc.zero ? 0 : lastSeen.counter;

  final String deviceId;
  final Clock clock;

  /// How far ahead of this device's wall clock a peer's timestamp may be
  /// before we refuse it.
  ///
  /// A device whose date is set to 2031 must not be able to poison the merge
  /// order for the next five years by making every one of its rows win every
  /// conflict forever.
  final Duration maxDrift;

  int _millis;
  int _counter;

  /// The last timestamp issued or merged.
  Hlc get last =>
      Hlc.of(millis: _millis, counter: _counter, deviceId: deviceId);

  /// Issues the next timestamp for a local write.
  Hlc next() {
    final physical = clock.nowUtc().millisecondsSinceEpoch;
    if (physical > _millis) {
      _millis = physical;
      _counter = 0;
    } else {
      // The wall clock is level with, or behind, logical time. Either way
      // logical time only moves forward.
      _counter++;
      if (_counter > Hlc._maxCounter) {
        _millis++;
        _counter = 0;
      }
    }
    return last;
  }

  /// Folds a timestamp received from a peer into this clock.
  ///
  /// Throws [HlcDriftException] if the peer is implausibly far ahead, because
  /// accepting it would silently hand that device permanent priority in every
  /// future conflict.
  Hlc merge(Hlc remote) {
    final physical = clock.nowUtc().millisecondsSinceEpoch;
    if (remote.millis - physical > maxDrift.inMilliseconds) {
      throw HlcDriftException(
        remote: remote,
        localMillis: physical,
        maxDrift: maxDrift,
      );
    }

    final highest = [physical, _millis, remote.millis].reduce(
      (a, b) => a > b ? a : b,
    );

    if (highest == _millis && highest == remote.millis) {
      _counter = (_counter > remote.counter ? _counter : remote.counter) + 1;
    } else if (highest == _millis) {
      _counter++;
    } else if (highest == remote.millis) {
      _counter = remote.counter + 1;
    } else {
      _counter = 0;
    }
    _millis = highest;

    if (_counter > Hlc._maxCounter) {
      _millis++;
      _counter = 0;
    }
    return last;
  }
}

/// Thrown when a peer's clock is too far ahead to trust.
class HlcDriftException implements Exception {
  const HlcDriftException({
    required this.remote,
    required this.localMillis,
    required this.maxDrift,
  });

  final Hlc remote;
  final int localMillis;
  final Duration maxDrift;

  @override
  String toString() {
    final ahead = Duration(milliseconds: remote.millis - localMillis);
    return 'Device ${remote.deviceId} is ${ahead.inMinutes} minutes ahead of '
        'this one, past the ${maxDrift.inMinutes}-minute limit. Check the date '
        'and time on both devices before syncing.';
  }
}
