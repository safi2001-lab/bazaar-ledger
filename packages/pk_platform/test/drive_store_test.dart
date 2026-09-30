import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pk_platform/pk_platform.dart';
import 'package:test/test.dart';

/// The Drive store against a stand-in for Google Drive on this machine.
void main() {
  late HttpServer drive;
  late Map<String, (String name, DateTime at, Uint8List bytes)> held;
  late List<String> auth;
  var next = 0;
  var refuse = false;

  setUp(() async {
    held = {};
    auth = [];
    refuse = false;
    drive = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    drive.listen((request) async {
      auth.add(request.headers.value(HttpHeaders.authorizationHeader) ?? '');
      final body = await request.fold<BytesBuilder>(
        BytesBuilder(),
        (b, d) => b..add(d),
      );
      final path = request.uri.path;
      final out = request.response;
      Map<String, Object?> json(String id) => {
        'id': id,
        'name': held[id]!.$1,
        'createdTime': held[id]!.$2.toIso8601String(),
        'size': '${held[id]!.$3.length}',
      };
      if (refuse) {
        out.statusCode = 401;
      } else if (request.method == 'POST' && path == '/upload/drive/v3/files') {
        // Pull the two parts out of multipart/related.
        final type = request.headers.contentType!;
        expect(type.mimeType, 'multipart/related');
        final boundary = type.parameters['boundary']!;
        final raw = latin1.decode(body.takeBytes());
        final parts = raw.split('--$boundary');
        final meta =
            jsonDecode(parts[1].split('\r\n\r\n')[1].trim())
                as Map<String, Object?>;
        expect(meta['parents'], ['appDataFolder']);
        final content = parts[2].split('\r\n\r\n')[1];
        final bytes = Uint8List.fromList(
          latin1.encode(content.substring(0, content.length - 2)),
        );
        final id = 'f${next++}';
        held[id] = (
          meta['name']! as String,
          DateTime.utc(2026, 9, 1).add(Duration(days: next)),
          bytes,
        );
        out.write(jsonEncode(json(id)));
      } else if (request.method == 'GET' && path == '/drive/v3/files') {
        expect(request.uri.queryParameters['spaces'], 'appDataFolder');
        out.write(
          jsonEncode({
            'files': [for (final id in held.keys) json(id)],
          }),
        );
      } else if (request.method == 'GET' &&
          path.startsWith('/drive/v3/files/')) {
        expect(request.uri.queryParameters['alt'], 'media');
        out.add(held[path.split('/').last]!.$3);
      } else if (request.method == 'DELETE') {
        held.remove(path.split('/').last);
        out.statusCode = 204;
      } else {
        out.statusCode = 404;
      }
      await out.close();
    });
  });

  tearDown(() => drive.close(force: true));

  DriveBackupStore store({String? token = 'drive-token'}) => DriveBackupStore(
    accessToken: () async => token,
    api: 'http://127.0.0.1:${drive.port}',
  );

  group('drive backup store', () {
    test('uploads, lists newest first, downloads and deletes', () async {
      final bytes = Uint8List.fromList([for (var i = 0; i < 300; i++) i % 256]);
      final first = await store().upload('a.pkbak', bytes);
      await store().upload('b.pkbak', Uint8List.fromList([1, 2, 3]));

      expect(first.name, 'a.pkbak');
      expect(first.bytes, 300);
      expect(auth, everyElement('Bearer drive-token'));

      final list = await store().list();
      expect([for (final f in list) f.name], ['b.pkbak', 'a.pkbak']);

      expect(await store().download(first.id), bytes);

      await store().delete(first.id);
      expect([for (final f in await store().list()) f.name], ['b.pkbak']);
    });

    test('with no sign-in, nothing is sent and it says so', () async {
      await expectLater(
        store(token: null).list(),
        throwsA(
          isA<CloudBackupFailed>().having(
            (f) => f.signInAgain,
            'signInAgain',
            isTrue,
          ),
        ),
      );
      expect(auth, isEmpty);
    });

    test('a refused token asks the shopkeeper to connect again', () async {
      refuse = true;
      await expectLater(
        store().list(),
        throwsA(
          isA<CloudBackupFailed>().having(
            (f) => f.signInAgain,
            'signInAgain',
            isTrue,
          ),
        ),
      );
    });

    test('no connection is a failure in words, not a crash', () async {
      final port = drive.port;
      await drive.close(force: true);
      final gone = DriveBackupStore(
        accessToken: () async => 't',
        api: 'http://127.0.0.1:$port',
      );
      await expectLater(
        gone.list(),
        throwsA(
          isA<CloudBackupFailed>().having(
            (f) => f.reason,
            'reason',
            contains('No connection'),
          ),
        ),
      );
    });
  });
}
