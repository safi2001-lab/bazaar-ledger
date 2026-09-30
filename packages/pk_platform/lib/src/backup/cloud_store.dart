import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// One sealed backup kept in the cloud.
final class CloudBackupFile {
  const CloudBackupFile({
    required this.id,
    required this.name,
    required this.createdUtc,
    required this.bytes,
  });

  final String id;
  final String name;
  final DateTime createdUtc;
  final int bytes;
}

/// Why the cloud would not take or give a backup, in words.
final class CloudBackupFailed implements Exception {
  const CloudBackupFailed(this.reason, {this.signInAgain = false});

  final String reason;

  /// Google no longer accepts this phone's sign-in; the shopkeeper has to
  /// connect again from the Backup screen.
  final bool signInAgain;

  @override
  String toString() => reason;
}

/// Somewhere sealed backups are kept off the phone (M20).
///
/// Only `.pkbak` files go through it, already sealed with the shop's
/// passphrase: whoever holds the store holds bytes they cannot open.
abstract interface class CloudBackupStore {
  Future<CloudBackupFile> upload(String name, Uint8List bytes);

  /// Newest first.
  Future<List<CloudBackupFile>> list();
  Future<Uint8List> download(String id);
  Future<void> delete(String id);
}

/// The shop's own Google Drive, in the app's private folder.
///
/// Scope `drive.appdata` only: a hidden folder this app alone can see,
/// which the shopkeeper can size and empty from Drive's settings, and
/// nothing else on their Drive is readable to it. Drive REST v3 over
/// `HttpClient`; the access token comes from Google sign-in on the phone.
final class DriveBackupStore implements CloudBackupStore {
  DriveBackupStore({
    required this.accessToken,
    this.api = 'https://www.googleapis.com',
    this.timeout = const Duration(seconds: 60),
  });

  /// A current access token for scope `drive.appdata`, or null when the
  /// phone is not signed in.
  final Future<String?> Function() accessToken;
  final String api;
  final Duration timeout;

  static const scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const _fields = 'id,name,createdTime,size';

  Future<String> _token() async {
    final token = await accessToken();
    if (token == null || token.isEmpty) {
      throw const CloudBackupFailed(
        'Not connected to Google Drive. Connect it on the Backup screen.',
        signInAgain: true,
      );
    }
    return token;
  }

  Future<(int, List<int>)> _send(
    String method,
    Uri uri, {
    List<int>? body,
    String? contentType,
  }) async {
    final token = await _token();
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (contentType != null) {
        request.headers.set(HttpHeaders.contentTypeHeader, contentType);
      }
      if (body != null) {
        request.contentLength = body.length;
        request.add(body);
      }
      final response = await request.close().timeout(timeout);
      final bytes = await response
          .fold<BytesBuilder>(BytesBuilder(copy: false), (b, d) => b..add(d))
          .timeout(timeout);
      final status = response.statusCode;
      if (status == 401 || status == 403) {
        throw CloudBackupFailed(
          'Google Drive refused this phone ($status). Connect it again on '
          'the Backup screen.',
          signInAgain: true,
        );
      }
      if (status >= 300) {
        throw CloudBackupFailed('Google Drive answered $status.');
      }
      return (status, bytes.takeBytes());
    } on SocketException {
      throw const CloudBackupFailed('No connection to Google Drive.');
    } on TimeoutException {
      throw const CloudBackupFailed('Google Drive did not answer in time.');
    } on HttpException {
      throw const CloudBackupFailed('The connection to Google Drive broke.');
    } finally {
      client.close(force: true);
    }
  }

  static CloudBackupFile _file(Map<String, Object?> json) => CloudBackupFile(
    id: '${json['id']}',
    name: '${json['name'] ?? ''}',
    createdUtc:
        DateTime.tryParse('${json['createdTime'] ?? ''}')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    bytes: int.tryParse('${json['size'] ?? ''}') ?? 0,
  );

  static Map<String, Object?> _json(List<int> bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is Map<String, Object?>) return decoded;
    throw const CloudBackupFailed('Google Drive sent something unexpected.');
  }

  @override
  Future<CloudBackupFile> upload(String name, Uint8List bytes) async {
    final boundary =
        'bazaar-${Random.secure().nextInt(1 << 32).toRadixString(16)}';
    final meta = jsonEncode({
      'name': name,
      'parents': ['appDataFolder'],
    });
    final body = BytesBuilder(copy: false)
      ..add(
        utf8.encode(
          '--$boundary\r\n'
          'Content-Type: application/json; charset=UTF-8\r\n\r\n'
          '$meta\r\n'
          '--$boundary\r\n'
          'Content-Type: application/octet-stream\r\n\r\n',
        ),
      )
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));
    final (_, answer) = await _send(
      'POST',
      Uri.parse(
        '$api/upload/drive/v3/files?uploadType=multipart&fields=$_fields',
      ),
      body: body.takeBytes(),
      contentType: 'multipart/related; boundary=$boundary',
    );
    return _file(_json(answer));
  }

  @override
  Future<List<CloudBackupFile>> list() async {
    final uri = Uri.parse('$api/drive/v3/files').replace(
      queryParameters: {
        'spaces': 'appDataFolder',
        'fields': 'files($_fields)',
        'orderBy': 'createdTime desc',
        'pageSize': '100',
      },
    );
    final (_, answer) = await _send('GET', uri);
    final files = _json(answer)['files'];
    final list = [
      if (files is List)
        for (final f in files)
          if (f is Map<String, Object?>) _file(f),
    ]..sort((a, b) => b.createdUtc.compareTo(a.createdUtc));
    return list;
  }

  @override
  Future<Uint8List> download(String id) async {
    final (_, bytes) = await _send(
      'GET',
      Uri.parse('$api/drive/v3/files/${Uri.encodeComponent(id)}?alt=media'),
    );
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> delete(String id) async {
    await _send(
      'DELETE',
      Uri.parse('$api/drive/v3/files/${Uri.encodeComponent(id)}'),
    );
  }
}
