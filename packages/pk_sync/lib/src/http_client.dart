import 'dart:convert';
import 'dart:io';

import 'peer.dart';
import 'wire.dart';

/// The master, as a counter sees it: a [SyncPeer] at the other end of the
/// shop's wi-fi.
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

  /// Asks the master at [host] to let this phone join, with the [code] it
  /// shows.
  static Future<JoinGrant> join({
    required String host,
    required String code,
    required String label,
    required String platform,
    int port = defaultSyncPort,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final json = await _post(
      host,
      port,
      '/v1/join',
      {'code': code, 'label': label, 'platform': platform},
      key: null,
      timeout: timeout,
    );
    return JoinGrant.fromJson(json);
  }

  @override
  Future<VersionVector> vector() async {
    final json = await _call('/v1/vector', const {});
    final v = json['vector']! as Map<String, Object?>;
    return {for (final e in v.entries) e.key: e.value! as int};
  }

  @override
  Future<List<SyncChange>> changesSince(VersionVector known) async {
    final json = await _call('/v1/pull', {'vector': known});
    return [
      for (final r in json['changes']! as List<Object?>)
        SyncChange(r! as Map<String, Object?>),
    ];
  }

  @override
  Future<ApplyResult> apply(List<SyncChange> changes) async {
    final json = await _call('/v1/push', {
      'changes': [for (final c in changes) c.row],
    });
    return ApplyResult.fromJson(json);
  }

  Future<Map<String, Object?>> _call(String path, Object body) =>
      _post(host, port, path, body, key: syncKey, timeout: timeout);

  static Future<Map<String, Object?>> _post(
    String host,
    int port,
    String path,
    Object body, {
    required String? key,
    required Duration timeout,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.post(host, port, path).timeout(timeout);
      request.headers.contentType = ContentType.json;
      if (key != null) request.headers.set(syncKeyHeader, key);
      request.add(utf8.encode(jsonEncode(body)));
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
    } on HttpException {
      throw SyncRefused('The connection to the master at $host broke.');
    } finally {
      client.close(force: true);
    }
  }
}
