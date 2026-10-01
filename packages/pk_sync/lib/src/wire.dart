import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The port a master listens on unless told otherwise. Above the range
/// Android reserves and away from the printers' 9100.
const defaultSyncPort = 47470;

/// Bumped when the wire format changes in a way an older build cannot read.
const syncProtocolVersion = 2;

/// The largest body either side will read. A shop's whole history as JSON
/// is a few megabytes; this is a ceiling against a stray client, not a
/// budget.
const maxSyncBodyBytes = 256 * 1024 * 1024;

Future<Object?> readJsonBody(HttpRequest request) async =>
    _decode(request, request.contentLength);

Future<Object?> readJsonResponse(HttpClientResponse response) async =>
    _decode(response, response.contentLength);

Future<Object?> _decode(Stream<List<int>> body, int declared) async {
  if (declared > maxSyncBodyBytes) {
    throw const FormatException('body too large');
  }
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in body) {
    bytes.add(chunk);
    if (bytes.length > maxSyncBodyBytes) {
      throw const FormatException('body too large');
    }
  }
  if (bytes.isEmpty) return null;
  return jsonDecode(utf8.decode(bytes.takeBytes()));
}

/// Compares two keys in time that does not depend on where they differ.
bool sameKey(String a, String b) {
  final x = utf8.encode(a);
  final y = utf8.encode(b);
  var diff = x.length ^ y.length;
  for (var i = 0; i < x.length && i < y.length; i++) {
    diff |= x[i] ^ y[i];
  }
  return diff == 0;
}
