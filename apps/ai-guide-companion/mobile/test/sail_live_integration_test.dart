import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guide_companion/ai/sail_token.dart';
import 'package:guide_companion/ai/ai_gateway.dart';
import 'package:guide_companion/ai/ai_settings.dart';
import 'package:http/http.dart' as http;

void main() {
  test('live SAIL token signing', () async {
    final ak = Platform.environment['SAIL_AK'];
    final sk = Platform.environment['SAIL_SK'];
    final app = Platform.environment['SAIL_APP'];
    if (ak == null || sk == null || app == null) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    const expiration = 86400;
    final signature = const SailTokenSigner().signature(
      accessKey: ak,
      secretKey: sk,
      timestamp: timestamp,
      expiration: expiration,
    );
    final uri = Uri.parse('https://sami.bytedance.com/internal/api/v1/token')
        .replace(
          queryParameters: {
            'version': 'auth-v1',
            'access_key': ak,
            'appkey': app,
            'timestamp': '$timestamp',
            'expiration': '$expiration',
            'signature': signature,
          },
        );
    final response = await http.get(uri);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    expect(payload.remove('token'), isNotNull);
    expect(payload['status_code'], 20000000);
  }, tags: 'live');

  test('live SAIL TTS returns decodable WAV audio', () async {
    final ak = Platform.environment['SAIL_AK'];
    final sk = Platform.environment['SAIL_SK'];
    final app = Platform.environment['SAIL_APP'];
    if (ak == null || sk == null || app == null) return;

    final gateway = AiGateway(
      AiSettings(
        speechAppId: app,
        speechAccessKey: ak,
        speechSecretKey: sk,
        ttsVoice: 'zh_female_qingxin',
      ),
    );
    final audio = await gateway.synthesize('你好，我是微光导游。');

    expect(audio.sublist(0, 4), [0x52, 0x49, 0x46, 0x46]);
    expect(audio.length, greaterThan(1000));
  }, tags: 'live');
}
