import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:pakistan_sme_billing/core/utils/hlc.dart';
import 'package:pakistan_sme_billing/data/database/app_database.dart';
import 'package:pakistan_sme_billing/services/p2p_sync_service.dart';

void main() {
  test('HLC Clock strictly orders simultaneous transactions across nodes', () {
    final hlcA = Hlc.now('NODE_COUNTER_1');
    final hlcB = Hlc.now('NODE_COUNTER_2');

    // Send event from A
    final sendA = hlcA.send();
    // B receives event from A
    final recvB = hlcB.receive(sendA);

    expect(recvB.compareTo(sendA), isPositive);
  });

  test('P2pSyncService starts embedded shelf server and handles handshake and PIN security', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final service = P2pSyncService(
      db: db,
      nodeId: 'MASTER_1',
      pairingPin: '4321',
    );

    // Start embedded master server on port 8099
    final port = await service.startMasterServer(port: 8099);
    expect(port, equals(8099));
    expect(service.isServerRunning, isTrue);

    final client = http.Client();
    try {
      // 1. Test ping
      final pingRes = await client.get(Uri.parse('http://127.0.0.1:$port/api/v1/ping'));
      expect(pingRes.statusCode, 200);
      final pingData = jsonDecode(pingRes.body);
      expect(pingData['status'], 'online');
      expect(pingData['nodeId'], 'MASTER_1');

      // 2. Test invalid PIN rejection
      final badPinRes = await client.get(
        Uri.parse('http://127.0.0.1:$port/api/v1/sync/pull'),
        headers: {'x-pairing-pin': '0000'},
      );
      expect(badPinRes.statusCode, 403);

      // 3. Test valid PIN access
      final goodPinRes = await client.get(
        Uri.parse('http://127.0.0.1:$port/api/v1/sync/pull'),
        headers: {'x-pairing-pin': '4321'},
      );
      expect(goodPinRes.statusCode, 200);
    } finally {
      client.close();
      await service.stopMasterServer();
      await db.close();
    }
  });
}
