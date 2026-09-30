import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pk_domain/pk_domain.dart';

/// FBR's Digital Invoicing gateway over HTTPS (M19).
///
/// FBR whitelists the IP a request comes from, and a phone has none it can
/// keep, so most shops reach the gateway through a licensed integrator or a
/// small proxy with a fixed address. [baseUrl] is that address; the default
/// is FBR's own gateway, for a shop that has one whitelisted.
final class FbrClient implements FbrGateway {
  FbrClient({
    required this.token,
    this.sandbox = true,
    String? baseUrl,
    this.timeout = const Duration(seconds: 30),
  }) : baseUrl = (baseUrl == null || baseUrl.trim().isEmpty)
           ? defaultBaseUrl
           : baseUrl.trim();

  static const defaultBaseUrl = 'https://gw.fbr.gov.pk/di_data/v1/di/';

  final String token;
  final bool sandbox;
  final String baseUrl;
  final Duration timeout;

  Uri get postUri => Uri.parse(
    '${baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'}'
    '${sandbox ? 'postinvoicedata_sb' : 'postinvoicedata'}',
  );

  @override
  Future<FbrOutcome> post(String payloadJson) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.postUrl(postUri).timeout(timeout);
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.add(utf8.encode(payloadJson));
      final response = await request.close().timeout(timeout);
      final text = await utf8.decodeStream(response).timeout(timeout);
      Object? body;
      try {
        body = text.isEmpty ? null : jsonDecode(text);
      } on FormatException {
        body = null;
      }
      return readFbrResponse(response.statusCode, body);
    } on SocketException {
      return const FbrTryLater('No connection to FBR.');
    } on TimeoutException {
      return const FbrTryLater('FBR did not answer in time.');
    } on HttpException {
      return const FbrTryLater('The connection to FBR broke.');
    } finally {
      client.close(force: true);
    }
  }
}
