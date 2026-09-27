import 'dart:io';
import 'dart:math';

import 'package:pk_sync/pk_sync.dart';
import 'package:test/test.dart';

/// A peer that keeps its outbox in a list, for the exchange alone.
final class _MemoryPeer implements SyncPeer {
  _MemoryPeer(this.deviceId);

  final String deviceId;
  final List<SyncChange> log = [];
  int _seq = 0;

  void write(String what) => log.add(
    SyncChange({'origin_device_id': deviceId, 'seq': ++_seq, 'what': what}),
  );

  List<String> get held => [for (final c in log) c.row['what']! as String];

  @override
  Future<VersionVector> vector() async {
    final v = <String, int>{};
    for (final c in log) {
      if (c.seq > (v[c.originDeviceId] ?? 0)) v[c.originDeviceId] = c.seq;
    }
    return v;
  }

  @override
  Future<List<SyncChange>> changesSince(VersionVector known) async =>
      unseen(log, known);

  @override
  Future<ApplyResult> apply(List<SyncChange> changes) async {
    final have = await vector();
    var applied = 0;
    var skipped = 0;
    for (final c in changes) {
      if (c.seq <= (have[c.originDeviceId] ?? 0)) {
        skipped++;
        continue;
      }
      log.add(c);
      have[c.originDeviceId] = c.seq;
      applied++;
    }
    return ApplyResult(applied: applied, skipped: skipped, conflicts: 0);
  }
}

void main() {
  group('sync exchange', () {
    test(
      'two counters are level after one round each through the master',
      () async {
        final master = _MemoryPeer('M')..write('m1');
        final a = _MemoryPeer('A')..write('a1');
        final b = _MemoryPeer('B')
          ..write('b1')
          ..write('b2');

        await exchange(a, master);
        await exchange(b, master);
        await exchange(a, master);

        expect(master.held.toSet(), {'m1', 'a1', 'b1', 'b2'});
        expect(a.held.toSet(), {'m1', 'a1', 'b1', 'b2'});
        expect(b.held.toSet(), {'m1', 'a1', 'b1', 'b2'});
      },
    );

    test('a round with nothing new moves nothing', () async {
      final master = _MemoryPeer('M')..write('m1');
      final a = _MemoryPeer('A')..write('a1');
      await exchange(a, master);
      final again = await exchange(a, master);
      expect(again.sent.applied, 0);
      expect(again.received.applied, 0);
      expect(master.log, hasLength(2));
    });
  });

  group('sync over http', () {
    late _MemoryPeer master;
    late SyncHost host;
    late int port;

    setUp(() async {
      master = _MemoryPeer('M')..write('m1');
      host = SyncHost(
        peer: master,
        syncKey: () => 'the-key',
        admit: ({required label, required platform}) async => JoinGrant(
          firmId: 'F',
          deviceId: 'D-$label',
          syncKey: 'the-key',
          shopName: 'Ali Kiryana',
        ),
        random: Random(7),
      );
      port = await host.start(port: 0, address: InternetAddress.loopbackIPv4);
    });

    tearDown(() => host.dispose());

    test('a counter joins with the code and then syncs with the key', () async {
      final code = host.openForJoining();
      final grant = await RemotePeer.join(
        host: '127.0.0.1',
        port: port,
        code: code,
        label: 'Counter 2',
        platform: 'android',
      );
      expect(grant.deviceId, 'D-Counter 2');
      expect(grant.shopName, 'Ali Kiryana');
      expect(host.pairingCode, isNull, reason: 'one join per code');

      final counter = _MemoryPeer('C')..write('c1');
      final remote = RemotePeer(
        host: '127.0.0.1',
        port: port,
        syncKey: grant.syncKey,
      );
      final pushed = host.changed.first;
      final report = await exchange(counter, remote);
      expect(report.sent.applied, 1);
      expect(report.received.applied, 1);
      expect((await pushed).applied, 1);
      expect(master.held, ['m1', 'c1']);
      expect(counter.held, ['c1', 'm1']);
    });

    test('a wrong key is refused and nothing moves', () async {
      final counter = _MemoryPeer('C')..write('c1');
      final remote = RemotePeer(
        host: '127.0.0.1',
        port: port,
        syncKey: 'guessed',
      );
      await expectLater(exchange(counter, remote), throwsA(isA<SyncRefused>()));
      expect(master.held, ['m1']);
    });

    test(
      'joining is shut until opened, and five wrong codes shut it',
      () async {
        Future<JoinGrant> tryCode(String code) => RemotePeer.join(
          host: '127.0.0.1',
          port: port,
          code: code,
          label: 'X',
          platform: 'android',
        );
        await expectLater(tryCode('000000'), throwsA(isA<SyncRefused>()));

        final code = host.openForJoining();
        final wrong = code == '111111' ? '222222' : '111111';
        for (var i = 0; i < 5; i++) {
          await expectLater(tryCode(wrong), throwsA(isA<SyncRefused>()));
        }
        expect(host.pairingCode, isNull);
        await expectLater(tryCode(code), throwsA(isA<SyncRefused>()));
      },
    );

    test('a master that is not there is said in words', () async {
      await host.stop();
      final remote = RemotePeer(
        host: '127.0.0.1',
        port: port,
        syncKey: 'the-key',
        timeout: const Duration(seconds: 2),
      );
      await expectLater(
        remote.vector(),
        throwsA(
          isA<SyncRefused>().having(
            (e) => e.reason,
            'reason',
            contains("shop's wi-fi"),
          ),
        ),
      );
    });
  });
}
