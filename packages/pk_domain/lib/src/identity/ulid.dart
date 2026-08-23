import 'dart:math';

/// Generates identifiers for every row the application writes.
abstract interface class IdGenerator {
  /// A fresh, unique, lexicographically sortable identifier.
  String next();
}

/// A ULID generator.
///
/// Every primary key in this database is a ULID and not an autoincrementing
/// integer, because two tills on the same shop Wi-Fi both allocating `id = 41`
/// makes LAN sync impossible without renumbering every foreign key in the
/// database at merge time. A ULID is generated independently on each device
/// and never collides.
///
/// The encoding is 26 characters of Crockford base32: 48 bits of millisecond
/// timestamp followed by 80 bits of randomness. Because the timestamp leads
/// and base32 preserves ordering, sorting ULIDs as strings sorts them by
/// creation time — which is why the sales list can page by primary key with no
/// secondary sort and no `created_at` index.
///
/// Within a single millisecond the random component is incremented rather than
/// redrawn, so ids minted in a tight loop stay strictly increasing. A cashier
/// scanning fifteen barcodes in one second must not produce lines that sort
/// into a different order than they were rung up in.
final class UlidGenerator implements IdGenerator {
  UlidGenerator({Random? random, DateTime Function()? now})
      : _random = random ?? Random.secure(),
        _now = now ?? DateTime.now;

  final Random _random;
  final DateTime Function() _now;

  int _lastMillis = -1;
  final List<int> _lastRandom = List<int>.filled(_randomLength, 0);

  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const int _timeLength = 10;
  static const int _randomLength = 16;

  /// The largest timestamp a 48-bit ULID can carry: 10889-08-02.
  static const int maxMillis = 281474976710655;

  @override
  String next() {
    final millis = _now().toUtc().millisecondsSinceEpoch;
    if (millis < 0 || millis > maxMillis) {
      throw ArgumentError.value(
        millis,
        'millis',
        'outside the range a ULID timestamp can encode',
      );
    }

    if (millis > _lastMillis) {
      _lastMillis = millis;
      _fillRandom();
    } else {
      // Either the clock has not ticked, or it has gone BACKWARDS — an NTP
      // correction, or a shopkeeper fixing the date in Settings, both routine.
      // In both cases we hold the highest millisecond seen and increment the
      // random block, because redrawing it here would make the new id sort
      // before ones already written roughly half the time.
      _incrementRandom();
    }

    final buffer = StringBuffer();
    var remaining = _lastMillis;
    final timeChars = List<String>.filled(_timeLength, '0');
    for (var i = _timeLength - 1; i >= 0; i--) {
      timeChars[i] = _alphabet[remaining % 32];
      remaining ~/= 32;
    }
    buffer.writeAll(timeChars);
    for (final v in _lastRandom) {
      buffer.write(_alphabet[v]);
    }
    return buffer.toString();
  }

  void _fillRandom() {
    for (var i = 0; i < _randomLength; i++) {
      _lastRandom[i] = _random.nextInt(32);
    }
  }

  void _incrementRandom() {
    for (var i = _randomLength - 1; i >= 0; i--) {
      if (_lastRandom[i] < 31) {
        _lastRandom[i]++;
        return;
      }
      _lastRandom[i] = 0;
    }
    // 2^80 ids in one millisecond. Reaching here means something is very
    // wrong, and silently wrapping would start reusing primary keys.
    throw StateError('ULID random component overflowed within one millisecond');
  }

  /// The millisecond timestamp encoded in [ulid].
  ///
  /// Used by the reconciler and by data-health checks, never on a hot path —
  /// the row's own `created_at_utc` is the column reports read.
  static DateTime timestampOf(String ulid) {
    if (!isValid(ulid)) {
      throw FormatException('Not a ULID', ulid);
    }
    var millis = 0;
    for (var i = 0; i < _timeLength; i++) {
      millis = millis * 32 + _alphabet.indexOf(ulid[i]);
    }
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  /// Whether [value] is a syntactically valid ULID.
  static bool isValid(String value) {
    if (value.length != _timeLength + _randomLength) return false;
    for (var i = 0; i < value.length; i++) {
      if (!_alphabet.contains(value[i])) return false;
    }
    return true;
  }
}
