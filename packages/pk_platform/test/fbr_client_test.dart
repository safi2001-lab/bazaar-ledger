import 'dart:convert';
import 'dart:io';

import 'package:pk_domain/pk_domain.dart';
import 'package:pk_platform/pk_platform.dart';
import 'package:test/test.dart';

/// The client against a stand-in for FBR on this machine.
void main() {
  late HttpServer fbr;
  late List<(String path, String auth, String body)> seen;
  late (int, Object?) Function() answer;

  setUp(() async {
    seen = [];
    fbr = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    fbr.listen((request) async {
      seen.add((
        request.uri.path,
        request.headers.value(HttpHeaders.authorizationHeader) ?? '',
        await utf8.decodeStream(request),
      ));
      final (status, body) = answer();
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(body == null ? '' : jsonEncode(body));
      await request.response.close();
    });
  });

  tearDown(() => fbr.close(force: true));

  FbrClient client({bool sandbox = true}) => FbrClient(
    token: 'secret-token',
    sandbox: sandbox,
    baseUrl: 'http://127.0.0.1:${fbr.port}/di_data/v1/di',
  );

  group('fbr client', () {
    test('a bill is posted with the token and comes back numbered', () async {
      answer = () => (
        200,
        {
          'invoiceNumber': '7000007DI1747119701593',
          'validationResponse': {'statusCode': '00'},
        },
      );
      final outcome = await client().post('{"InvoiceType":"Sale Invoice"}');
      expect(outcome, isA<FbrPosted>());
      final (path, auth, body) = seen.single;
      expect(path, '/di_data/v1/di/postinvoicedata_sb');
      expect(auth, 'Bearer secret-token');
      expect(body, '{"InvoiceType":"Sale Invoice"}');
      await client(sandbox: false).post('{}');
      expect(seen.last.$1, '/di_data/v1/di/postinvoicedata');
    });

    test('a refusal is a refusal, and a gateway down is a retry', () async {
      answer = () => (200, {'ErrorCode': '1005', 'Message': 'Duplicate'});
      expect(await client().post('{}'), isA<FbrRejected>());
      answer = () => (503, null);
      expect(await client().post('{}'), isA<FbrTryLater>());
    });

    test('no connection is a retry, not a crash', () async {
      final port = fbr.port;
      await fbr.close(force: true);
      final outcome = await FbrClient(
        token: 't',
        baseUrl: 'http://127.0.0.1:$port/',
        timeout: const Duration(seconds: 2),
      ).post('{}');
      expect(outcome, isA<FbrTryLater>());
    });
  });
}
