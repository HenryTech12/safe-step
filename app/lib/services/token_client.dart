import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_mode.dart';
import '../models/language.dart';

class RoomTicket {
  const RoomTicket({required this.url, required this.token, required this.room});
  final String url;
  final String token;
  final String room;
}

class TokenException implements Exception {
  TokenException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => 'TokenException($statusCode): $message';
}

/// Fetches a LiveKit room token from the SafeStep token server.
/// The app never holds the LiveKit API secret.
class TokenClient {
  TokenClient({required this.baseUrl, http.Client? client}) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<RoomTicket> fetch({
    required AppLanguage language,
    required AppMode mode,
    required String installId,
  }) async {
    final uri = Uri.parse(baseUrl).resolve('/token');
    final resp = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'language': language.code, 'mode': mode.wire, 'install_id': installId}),
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw TokenException(resp.statusCode, resp.body);
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final url = j['url'] as String?;
    final token = j['token'] as String?;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      throw TokenException(500, 'invalid token response');
    }
    return RoomTicket(url: url, token: token, room: (j['room'] as String?) ?? '');
  }
}
