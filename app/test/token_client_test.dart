import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safestep/models/app_mode.dart';
import 'package:safestep/models/language.dart';
import 'package:safestep/services/token_client.dart';

void main() {
  test('posts language, mode and install id; never sends a secret', () async {
    late http.Request sent;
    final client = MockClient((req) async {
      sent = req;
      return http.Response(jsonEncode({'url': 'wss://x', 'token': 't', 'room': 'safestep-1'}), 200);
    });
    final t = await TokenClient(baseUrl: 'http://host:8765', client: client)
        .fetch(language: AppLanguage.pcm, mode: AppMode.navigation, installId: 'abc12345');
    expect(sent.url.toString(), 'http://host:8765/token');
    expect(jsonDecode(sent.body), {'language': 'pcm', 'mode': 'navigation', 'install_id': 'abc12345'});
    expect(t.url, 'wss://x');
    expect(t.room, 'safestep-1');
  });

  test('errors become TokenException', () async {
    final client = MockClient((_) async => http.Response('slow down', 429));
    expect(
      TokenClient(baseUrl: 'http://h', client: client)
          .fetch(language: AppLanguage.en, mode: AppMode.hazardDetection, installId: 'abc12345'),
      throwsA(isA<TokenException>().having((e) => e.statusCode, 'status', 429)),
    );
  });
}
