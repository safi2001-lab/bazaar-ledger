import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'peer.dart';
import 'seal.dart';
import 'wire.dart';

export 'wire.dart' show defaultSyncPort;

/// Lets a counter in: makes its device row and returns what it needs.
typedef AdmitCounter =
    Future<JoinGrant> Function({
      required String label,
      required String platform,
    });

/// The master's side: a small HTTP server on the shop's wi-fi that the
/// counters sync with.
///
/// Nothing is listened for until the owner turns it on, and a counter gets
/// in only with the six-digit code the master shows while it is open for
/// joining. Everything after that is sealed with the shop's sync key, which
/// never crosses the wire (see [WireSeal]).
final class SyncHost {
  SyncHost({
    required this.peer,
    required this.syncKey,
    required this.admit,
    Random? random,
    this.joinWork = defaultJoinWork,
  }) : _random = random ?? Random.secure();

  /// PBKDF2 rounds per guess of the joining code; lowered only in tests.
  final int joinWork;

  final SyncPeer peer;
  final String Function() syncKey;
  final AdmitCounter admit;
  final Random _random;

  HttpServer? _server;
  String? _pairingCode;
  Future<JoinKeys>? _joinKeys;
  (String, WireSeal)? _seal;
  int _wrongCodes = 0;
  final _changed = StreamController<ApplyResult>.broadcast();

  /// Fires after a counter's changes are taken in, so the master's screens
  /// can show them.
  Stream<ApplyResult> get changed => _changed.stream;

  bool get isRunning => _server != null;

  int? get port => _server?.port;

  /// The code a counter types to join, while joining is open.
  String? get pairingCode => _pairingCode;

  /// Starts listening on every interface, on [port].
  Future<int> start({
    int port = defaultSyncPort,
    InternetAddress? address,
  }) async {
    if (_server case final running?) return running.port;
    final server = await HttpServer.bind(
      address ?? InternetAddress.anyIPv4,
      port,
      shared: true,
    );
    _server = server;
    unawaited(server.forEach(_handle).catchError((Object _) {}));
    return server.port;
  }

  /// Opens joining and returns the code to show. One counter may join with
  /// it; five wrong codes close it.
  String openForJoining() {
    final code = _random.nextInt(1000000).toString().padLeft(6, '0');
    _pairingCode = code;
    _wrongCodes = 0;
    // A key pair for this joining only, so nothing learnt from one join
    // helps with the next.
    _joinKeys = JoinKeys.make();
    return code;
  }

  void closeJoining() {
    _pairingCode = null;
    _joinKeys = null;
  }

  /// The seal for the sync key as it stands, made once per key.
  Future<WireSeal?> _shopSeal() async {
    final key = syncKey();
    if (key.isEmpty) return null;
    final held = _seal;
    if (held != null && held.$1 == key) return held.$2;
    final seal = await WireSeal.forShop(key);
    _seal = (key, seal);
    return seal;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _pairingCode = null;
    _joinKeys = null;
    await server?.close(force: true);
  }

  Future<void> dispose() async {
    await stop();
    await _changed.close();
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/v2/hello') {
        final keys = _pairingCode == null ? null : await _joinKeys;
        return _send(response, {
          'app': 'bazaar-ledger',
          'protocol': syncProtocolVersion,
          'join_key': keys?.publicKey,
        });
      }
      if (request.method != 'POST') {
        return _fail(response, HttpStatus.methodNotAllowed, 'POST only');
      }
      final body = await readJsonBody(request);
      final json = body is Map<String, Object?>
          ? body
          : const <String, Object?>{};

      if (path == '/v2/join') return await _join(response, json);
      final seal = await _shopSeal();
      Map<String, Object?> opened;
      try {
        if (seal == null) throw const SyncRefused('no key');
        final inner = await seal.open(json);
        opened = inner is Map<String, Object?> ? inner : const {};
      } on SyncRefused {
        return _fail(
          response,
          HttpStatus.unauthorized,
          'This counter is not joined to this shop. Join it again from the '
          'master.',
        );
      }
      Future<void> answer(Object body) async =>
          _send(response, await seal.seal(body));
      switch (path) {
        case '/v2/vector':
          return answer({'vector': await peer.vector()});
        case '/v2/pull':
          final known = (opened['vector'] as Map<String, Object?>?) ?? const {};
          final changes = await peer.changesSince({
            for (final e in known.entries) e.key: e.value! as int,
          });
          return answer({
            'changes': [for (final c in changes) c.row],
          });
        case '/v2/push':
          final raw = (opened['changes'] as List<Object?>?) ?? const [];
          final result = await peer.apply([
            for (final r in raw) SyncChange(r! as Map<String, Object?>),
          ]);
          if (result.applied > 0 || result.conflicts > 0) {
            _changed.add(result);
          }
          return answer(result.toJson());
      }
      return _fail(response, HttpStatus.notFound, 'no such path');
    } on SyncRefused catch (e) {
      return _fail(response, HttpStatus.conflict, e.reason);
    } on FormatException catch (e) {
      return _fail(response, HttpStatus.badRequest, e.message);
    } on Object catch (e) {
      return _fail(response, HttpStatus.internalServerError, '$e');
    }
  }

  Future<void> _join(HttpResponse response, Map<String, Object?> json) async {
    final expected = _pairingCode;
    final keys = await _joinKeys;
    if (expected == null || keys == null) {
      return _fail(
        response,
        HttpStatus.forbidden,
        'The master is not letting counters join. Open joining on the '
        'master first.',
      );
    }
    // The counter's request opens only under the key both sides derive
    // from the exchange and the same code: a wrong code is a box that will
    // not open.
    final counterKey = '${json['pub'] ?? ''}';
    WireSeal? seal;
    Map<String, Object?>? asked;
    try {
      seal = await keys.sealWith(
        otherPublicKey: counterKey,
        code: expected,
        masterKey: keys.publicKey,
        counterKey: counterKey,
        work: joinWork,
      );
      final opened = await seal.open(json);
      if (opened is Map<String, Object?>) asked = opened;
    } on Object {
      asked = null;
    }
    if (asked == null || seal == null) {
      _wrongCodes++;
      if (_wrongCodes >= 5) closeJoining();
      return _fail(
        response,
        HttpStatus.forbidden,
        _pairingCode == null
            ? 'Too many wrong codes. Open joining on the master again.'
            : 'That is not the code the master shows.',
      );
    }
    closeJoining();
    final label = '${asked['label'] ?? ''}'.trim();
    final grant = await admit(
      label: label.isEmpty ? 'Counter' : label,
      platform: '${asked['platform'] ?? 'android'}',
    );
    return _send(response, await seal.seal(grant.toJson()));
  }

  static Future<void> _send(HttpResponse response, Object body) async {
    response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await response.close();
  }

  static Future<void> _fail(
    HttpResponse response,
    int status,
    String reason,
  ) async {
    response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'error': reason}));
    await response.close();
  }
}
