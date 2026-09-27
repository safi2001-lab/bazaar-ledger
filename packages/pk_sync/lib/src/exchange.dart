import 'peer.dart';

/// What one sync moved each way.
final class SyncReport {
  const SyncReport({required this.sent, required this.received});

  /// What the remote side did with what this side sent.
  final ApplyResult sent;

  /// What this side did with what it was sent.
  final ApplyResult received;

  int get conflicts => sent.conflicts + received.conflicts;
}

/// Brings two peers level: each gets every change the other has and it does
/// not, its own included when it came back round through a third device.
///
/// Push first, then pull. A counter that hands over its sales and then takes
/// the master's copy back receives in the same round whatever the master
/// merged from the other counters, so two tills are level after one round
/// each rather than two.
Future<SyncReport> exchange(SyncPeer local, SyncPeer remote) async {
  final remoteHas = await remote.vector();
  final outgoing = await local.changesSince(remoteHas);
  final sent = outgoing.isEmpty
      ? ApplyResult.none
      : await remote.apply(outgoing);

  final localHas = await local.vector();
  final incoming = await remote.changesSince(localHas);
  final received = incoming.isEmpty
      ? ApplyResult.none
      : await local.apply(incoming);
  return SyncReport(sent: sent, received: received);
}

/// The changes in [changes] that [known] does not already have.
///
/// For a peer that keeps its outbox in memory; a database answers the same
/// question in SQL.
List<SyncChange> unseen(Iterable<SyncChange> changes, VersionVector known) => [
  for (final c in changes)
    if (c.seq > (known[c.originDeviceId] ?? 0)) c,
];
