import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guide_companion/ai/ai_gateway.dart';
import 'package:guide_companion/ai/ai_settings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const settings = AiSettings(
    baseUrl: 'https://example.test',
    chatModel: 'guide-model',
    ttsModel: 'voice-model',
    apiKey: 'test-only',
  );

  test('parses an OpenAI-compatible chat response', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/v1/chat/completions');
      expect(request.headers['authorization'], 'Bearer test-only');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['model'], 'guide-model');
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'Walk toward the main theater.'},
            },
          ],
        }),
        200,
      );
    });

    final answer = await AiGateway(
      settings,
      client: client,
    ).chat('Where next?');
    expect(answer, 'Walk toward the main theater.');
  });

  test('returns TTS bytes and surfaces HTTP errors', () async {
    var success = true;
    final client = MockClient((request) async {
      if (success) return http.Response.bytes(Uint8List.fromList([1, 2]), 200);
      return http.Response('service unavailable', 503);
    });
    final gateway = AiGateway(settings, client: client);

    expect(await gateway.synthesize('Hello'), [1, 2]);
    success = false;
    expect(gateway.synthesize('Hello'), throwsA(isA<HttpException>()));
  });
}
