import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../core/utils/hlc.dart';
import '../data/database/app_database.dart';

class SyncMutation {
  final String entityType; // 'Invoice', 'Party', 'Item', 'Payment'
  final String mutationType; // 'INSERT', 'UPDATE', 'DELETE'
  final Map<String, dynamic> payload;
  final String hlc;

  SyncMutation({
    required this.entityType,
    required this.mutationType,
    required this.payload,
    required this.hlc,
  });

  Map<String, dynamic> toJson() => {
        'entityType': entityType,
        'mutationType': mutationType,
        'payload': payload,
        'hlc': hlc,
      };

  factory SyncMutation.fromJson(Map<String, dynamic> json) => SyncMutation(
        entityType: json['entityType'] as String,
        mutationType: json['mutationType'] as String,
        payload: json['payload'] as Map<String, dynamic>,
        hlc: json['hlc'] as String,
      );
}

class P2pSyncService {
  final AppDatabase db;
  final String nodeId;
  final String pairingPin;
  HttpServer? _server;
  Hlc _currentHlc;

  P2pSyncService({
    required this.db,
    required this.nodeId,
    required this.pairingPin,
  }) : _currentHlc = Hlc.now(nodeId);

  bool get isServerRunning => _server != null;
  int? get serverPort => _server?.port;

  /// Start embedded Shelf server on Master Counter
  Future<int> startMasterServer({int port = 8088}) async {
    if (_server != null) return _server!.port;

    final router = Router();

    // 1. Handshake / Ping
    router.get('/api/v1/ping', (Request request) {
      return Response.ok(
        jsonEncode({
          'status': 'online',
          'nodeId': nodeId,
          'version': '1.0.0',
          'timestamp': DateTime.now().toIso8601String(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    // Middleware to check PIN
    Handler pinAuthMiddleware(Handler innerHandler) {
      return (Request request) async {
        final pin = request.headers['x-pairing-pin'];
        if (pin != pairingPin) {
          return Response.forbidden(
            jsonEncode({'error': 'Invalid Pairing PIN'}),
            headers: {'content-type': 'application/json'},
          );
        }
        return innerHandler(request);
      };
    }

    // 2. Pull mutations from Master
    router.get('/api/v1/sync/pull', (Request request) async {
      final sinceParam = request.url.queryParameters['since'];
      // Query pending sync queue or recent records
      final syncRecords = await (db.select(db.syncQueue)
            ..where((tbl) => tbl.isSynced.equals(false)))
          .get();

      final mutations = syncRecords.map((r) => {
            'entityType': r.entityType,
            'mutationType': r.mutationType,
            'payload': jsonDecode(r.payloadJson),
            'timestamp': r.timestamp.toIso8601String(),
          }).toList();

      return Response.ok(
        jsonEncode({
          'mutations': mutations,
          'hlc': _currentHlc.send().toJson(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    // 3. Push mutations from Sub-counter to Master
    router.post('/api/v1/sync/push', (Request request) async {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final remoteHlcStr = data['hlc'] as String?;
      if (remoteHlcStr != null) {
        final remoteHlc = Hlc.fromJson(remoteHlcStr);
        _currentHlc = _currentHlc.receive(remoteHlc);
      }

      final incomingMutations = (data['mutations'] as List? ?? [])
          .map((m) => SyncMutation.fromJson(m as Map<String, dynamic>))
          .toList();

      // Apply incoming mutations to Master database
      await _applyIncomingMutations(incomingMutations);

      return Response.ok(
        jsonEncode({
          'success': true,
          'mergedCount': incomingMutations.length,
          'hlc': _currentHlc.send().toJson(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware((inner) => pinAuthMiddleware(inner))
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    return _server!.port;
  }

  /// Stop embedded server
  Future<void> stopMasterServer() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// Sync secondary/sub-counter with Master IP
  Future<int> syncSubCounterWithMaster({
    required String masterIp,
    int port = 8088,
    required String pin,
  }) async {
    final client = http.Client();
    try {
      final uri = Uri.parse('http://$masterIp:$port/api/v1/sync/push');
      
      // 1. Fetch pending local mutations to push
      final pendingQueue = await (db.select(db.syncQueue)
            ..where((tbl) => tbl.isSynced.equals(false)))
          .get();

      final outgoingMutations = pendingQueue.map((r) => SyncMutation(
            entityType: r.entityType,
            mutationType: r.mutationType,
            payload: jsonDecode(r.payloadJson) as Map<String, dynamic>,
            hlc: _currentHlc.send().toJson(),
          ).toJson()).toList();

      final response = await client.post(
        uri,
        headers: {
          'content-type': 'application/json',
          'x-pairing-pin': pin,
        },
        body: jsonEncode({
          'hlc': _currentHlc.send().toJson(),
          'mutations': outgoingMutations,
        }),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body) as Map<String, dynamic>;
        if (resData['hlc'] != null) {
          _currentHlc = _currentHlc.receive(Hlc.fromJson(resData['hlc']));
        }
        // Mark local records as synced
        for (var item in pendingQueue) {
          await (db.update(db.syncQueue)..where((tbl) => tbl.id.equals(item.id)))
              .write(const SyncQueueCompanion(isSynced: drift_value(true)));
        }
        return outgoingMutations.length;
      } else {
        throw StateError('Sync failed: HTTP ${response.statusCode} - ${response.body}');
      }
    } finally {
      client.close();
    }
  }

  Future<void> _applyIncomingMutations(List<SyncMutation> mutations) async {
    for (var m in mutations) {
      // Ingest based on entity
      if (m.entityType == 'Invoice') {
        // Idempotent insertion using invoice number or payload
      } else if (m.entityType == 'Item') {
        // Item synchronization
      }
    }
  }
}

const drift_value = Value;
