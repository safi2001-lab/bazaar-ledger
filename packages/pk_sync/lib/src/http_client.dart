import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'peer.dart';
import 'seal.dart';
import 'wire.dart';

/// The master, as a counter sees it: a [SyncPeer] at the other end of the
/// shop's wi-fi. Every body both ways is sealed with the shop's sync key
/// (see [WireSeal]); the key itself never leaves the phone.
final class RemotePeer implements SyncPeer {
  RemotePeer({
    required this.host,
    required this.syncKey,
    this.port = defaultSyncPort,
    this.timeout = const Duration(seconds: 20),
  });

  final String host;
  final int port;
  final String syncKey;
  final Duration timeout;

  Future<WireSeal>? _seal;

  /// Asks the master at [host] to let this phone join, with the [code] it
  /// shows. The code itself is never sent: it is mixed into a key the two
  /// phones agree on, and only a master showing the same code can open
  /// what this phone sends.
  static Future<JoinGrant> join({
    required String host,
    required String code,
    required String label,
    required String platform,
    int port = defaultSyncPort,
    Duration timeout = const Duration(seconds: 20),
    int work = defaultJoinWork,
  }) async {
    final hello = await _request(host, port, 'GET', '/v2/hello', null, timeout);
    final masterKey = hello['join_key'];
    if (masterKey is! String || masterKey.isEmpty) {
      throw const SyncRefused(
        'The master is not letting counters join. Open joining on the '
        'master first.',
      );
    }
    final mine = await JoinKeys.make();
    final seal = await mine.sealWith(
      otherPublicKey: masterKey,
      code: code.trim(),
      masterKey: masterKey,
      counterKey: mine.publicKey,
      work: work,
    );
    final answer = await _request(host, port, 'POST', '/v2/join', {
      'pub': mine.publicKey,
      ...await seal.seal({'label': label, 'platform': platform}),
    }, timeout);
    final grant = await seal.open(answer);
    if (grant is! Map<String, Object?>) {
      throw const SyncRefused('The master sent something unexpected.');
    }
    return JoinGrant.fromJson(grant);
  }

  @override
  Future<VersionVector> vector() async {
    final json = await _call('/v2/vector', const {});
    final v = json['vector']! as Map<String, Object?>;
    return {for (final e in v.entries) e.key: e.value! as int};
  }

  @override
  Future<List<SyncChange>> changesSince(VersionVector known) async {
    final json = await _call('/v2/pull', {'vector': known});
    return [
      for (final r in json['changes']! as List<Object?>)
        SyncChange(r! as Map<String, Object?>),
    ];
  }

  @override
  Future<ApplyResult> apply(List<SyncChange> changes) async {
    final json = await _call('/v2/push', {
      'changes': [for (final c in changes) c.row],
    });
    return ApplyResult.fromJson(json);
  }

  Future<Map<String, Object?>> _call(String path, Object body) async {
    final seal = await (_seal ??= WireSeal.forShop(syncKey));
    final answer = await _request(
      host,
      port,
      'POST',
      path,
      await seal.seal(body),
      timeout,
    );
    final opened = await seal.open(answer);
    return opened is Map<String, Object?> ? opened : const {};
  }

  static Future<Map<String, Object?>> _request(
    String host,
    int port,
    String method,
    String path,
    Object? body,
    Duration timeout,
  ) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .open(method, host, port, path)
          .timeout(timeout);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      }
      final response = await request.close().timeout(timeout);
      final json = await readJsonResponse(response);
      final map = json is Map<String, Object?>
          ? json
          : const <String, Object?>{};
      if (response.statusCode != HttpStatus.ok) {
        throw SyncRefused(
          '${map['error'] ?? 'The master answered ${response.statusCode}.'}',
        );
      }
      return map;
    } on SocketException {
      throw SyncRefused(
        'Cannot reach the master at $host. Check both phones are on the '
        "shop's wi-fi and the master has sync turned on.",
      );
    } on TimeoutException {
      // The same advice as a refusal, because on a shop's wi-fi it is the
      // same cause far more often than not: a phone that has left the
      // network, or a master with sync off, is met with silence rather than
      // a refusal (and Windows answers a closed port with silence too).
      // "Did not answer in time" on its own gives a shopkeeper nothing to do.
      throw SyncRefused(
        'The master at $host did not answer in time. Check both phones are '
        "on the shop's wi-fi and the master has sync turned on.",
      );
    } on HttpException {
      throw SyncRefused('The connection to the master at $host broke.');
    } finally {
      client.close(force: true);
    }
  }
}
