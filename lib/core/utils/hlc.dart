/// Hybrid Logical Clock (HLC) for deterministic timestamping and conflict resolution
/// across multi-counter devices without requiring an external NTP server or central internet cloud.
class Hlc implements Comparable<Hlc> {
  final int millis;
  final int counter;
  final String nodeId;

  Hlc({required this.millis, required this.counter, required this.nodeId});

  factory Hlc.now(String nodeId) {
    return Hlc(
      millis: DateTime.now().millisecondsSinceEpoch,
      counter: 0,
      nodeId: nodeId,
    );
  }

  Hlc send() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now > millis) {
      return Hlc(millis: now, counter: 0, nodeId: nodeId);
    }
    return Hlc(millis: millis, counter: counter + 1, nodeId: nodeId);
  }

  Hlc receive(Hlc remote) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final maxMillis = [now, millis, remote.millis].reduce((a, b) => a > b ? a : b);

    if (maxMillis == millis && maxMillis == remote.millis) {
      final maxCounter = [counter, remote.counter].reduce((a, b) => a > b ? a : b);
      return Hlc(millis: maxMillis, counter: maxCounter + 1, nodeId: nodeId);
    } else if (maxMillis == millis) {
      return Hlc(millis: maxMillis, counter: counter + 1, nodeId: nodeId);
    } else if (maxMillis == remote.millis) {
      return Hlc(millis: maxMillis, counter: remote.counter + 1, nodeId: nodeId);
    }
    return Hlc(millis: maxMillis, counter: 0, nodeId: nodeId);
  }

  @override
  int compareTo(Hlc other) {
    if (millis != other.millis) return millis.compareTo(other.millis);
    if (counter != other.counter) return counter.compareTo(other.counter);
    return nodeId.compareTo(other.nodeId);
  }

  String toJson() => '$millis:$counter:$nodeId';

  factory Hlc.fromJson(String json) {
    final parts = json.split(':');
    return Hlc(
      millis: int.parse(parts[0]),
      counter: int.parse(parts[1]),
      nodeId: parts[2],
    );
  }

  @override
  String toString() => toJson();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Hlc &&
          runtimeType == other.runtimeType &&
          millis == other.millis &&
          counter == other.counter &&
          nodeId == other.nodeId;

  @override
  int get hashCode => millis.hashCode ^ counter.hashCode ^ nodeId.hashCode;
}
