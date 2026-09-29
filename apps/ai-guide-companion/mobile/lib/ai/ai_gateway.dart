import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'ai_settings.dart';

final class AiGateway {
  AiGateway(this.settings, {http.Client? client})
    : client = client ?? http.Client();

  final AiSettings settings;
  final http.Client client;
  static const _timeout = Duration(seconds: 45);
  static const _maxTextBytes = 1024 * 1024;
  static const _maxAudioBytes = 12 * 1024 * 1024;

  Uri _uri(String path) {
    if (settings.baseUrl.trim().isEmpty) {
      throw StateError('Configure the AI base URL first');
    }
    final direct = Uri.tryParse(path);
    if (direct != null && direct.hasScheme) return direct;
    return Uri.parse(settings.baseUrl).resolve(path);
  }

  Map<String, String> get _headers => {
    if (settings.apiKey.isNotEmpty)
      'authorization': 'Bearer ${settings.apiKey}',
  };

  Future<String> transcribe(Uint8List wav) async {
    final request = http.MultipartRequest('POST', _uri(settings.sttPath))
      ..headers.addAll(_headers)
      ..fields['model'] = settings.sttModel
      ..files.add(
        http.MultipartFile.fromBytes('file', wav, filename: 'passport.wav'),
      );
    final response = await client.send(request).timeout(_timeout);
    final body = await _read(response, _maxTextBytes);
    _check(response.statusCode, body);
    final decoded = jsonDecode(utf8.decode(body));
    final text = decoded is Map ? decoded['text'] : null;
    if (text is! String || text.trim().isEmpty) {
      throw const FormatException('STT response has no text');
    }
    return text.trim();
  }

  Future<String> chat(
    String prompt, {
    List<Map<String, String>> history = const [],
  }) async {
    final response = await client
        .post(
          _uri(settings.chatPath),
          headers: {..._headers, 'content-type': 'application/json'},
          body: jsonEncode({
            'model': settings.chatModel,
            'messages': [
              {
                'role': 'system',
                'content':
                    'You are a concise, friendly travel guide. '
                    'Answer for spoken playback.',
              },
              ...history,
              {'role': 'user', 'content': prompt},
            ],
          }),
        )
        .timeout(_timeout);
    if (response.bodyBytes.length > _maxTextBytes) {
      throw const HttpException('Chat response is too large');
    }
    _check(response.statusCode, response.bodyBytes);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final choices = decoded is Map ? decoded['choices'] : null;
    Object? content;
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final choice = choices.first as Map;
      final message = choice['message'];
      if (message is Map) content = message['content'];
    }
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('Chat response has no message');
    }
    return content.trim();
  }

  Future<Uint8List> synthesize(String text) async {
    final response = await client
        .post(
          _uri(settings.ttsPath),
          headers: {..._headers, 'content-type': 'application/json'},
          body: jsonEncode({
            'model': settings.ttsModel,
            'voice': settings.voice,
            'input': text,
            'response_format': 'wav',
          }),
        )
        .timeout(_timeout);
    if (response.bodyBytes.length > _maxAudioBytes) {
      throw const HttpException('TTS response is too large');
    }
    _check(response.statusCode, response.bodyBytes);
    return response.bodyBytes;
  }

  static Future<Uint8List> _read(
    http.StreamedResponse response,
    int limit,
  ) async {
    final output = BytesBuilder(copy: false);
    await for (final part in response.stream.timeout(_timeout)) {
      if (output.length + part.length > limit) {
        throw const HttpException('Response is too large');
      }
      output.add(part);
    }
    return output.takeBytes();
  }

  static void _check(int status, Uint8List body) {
    if (status >= 200 && status < 300) return;
    final detail = utf8.decode(body.take(240).toList(), allowMalformed: true);
    throw HttpException('HTTP $status: $detail');
  }
}

final class HttpException implements Exception {
  const HttpException(this.message);
  final String message;

  @override
  String toString() => message;
}
