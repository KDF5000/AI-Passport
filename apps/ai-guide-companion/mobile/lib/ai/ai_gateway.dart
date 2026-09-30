import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

import 'ai_settings.dart';
import 'sail_token.dart';
import 'volc_speech_protocol.dart';

final class AiGateway {
  AiGateway(this.settings, {http.Client? client, WebSocketFactory? websocket})
    : client = client ?? http.Client(),
      websocket = websocket ?? _connectWebsocketWithHeaders;

  final AiSettings settings;
  final http.Client client;
  final WebSocketFactory websocket;
  static const _timeout = Duration(seconds: 45);
  static const _chatIdleTimeout = Duration(seconds: 90);
  static const _structuredChatTimeout = Duration(minutes: 4);
  static const _maxTextBytes = 1024 * 1024;
  static const _sailTokenSigner = SailTokenSigner();
  String? _cachedSailToken;
  DateTime? _cachedSailTokenExpiresAt;
  Future<String>? _pendingSailToken;

  Future<String> transcribePcm(Uint8List pcm, {int sampleRate = 16000}) async {
    if (pcm.isEmpty) throw StateError('No recorded audio');
    final channel = await _openAsrChannel().timeout(_timeout);
    final responses = _readAsrResponses(channel.stream).timeout(_timeout);
    var sequence = 1;
    final config = _asrConfigFrame(sequence, {
      'user': {'uid': 'passport-user'},
      'audio': {'format': 'pcm', 'rate': sampleRate, 'bits': 16, 'channel': 1},
      'request': {
        'model_name': 'bigmodel',
        'enable_itn': true,
        'enable_ddc': true,
        'enable_punc': true,
        'show_utterances': true,
        'result_type': 'full',
        'end_window_size': 800,
      },
    });
    try {
      channel.sink.add(config);
      final chunkSize = (sampleRate * 0.2 * 2).round();
      for (var offset = 0; offset < pcm.length; offset += chunkSize) {
        sequence += 1;
        final end = (offset + chunkSize).clamp(0, pcm.length);
        final isLast = end == pcm.length;
        channel.sink.add(
          _asrAudioFrame(
            sequence,
            Uint8List.sublistView(pcm, offset, end),
            isLast: isLast,
          ),
        );
      }
      return await responses;
    } finally {
      await channel.sink.close();
    }
  }

  Future<WebSocketChannel> _openAsrChannel() async {
    final connectId = _connectId();
    Object? lastError;
    for (final candidate in _asrCandidates()) {
      WebSocketChannel? channel;
      try {
        channel = await websocket(
          candidate.endpoint,
          _sailHeaders(connectId, candidate.resourceId),
        );
        await channel.ready;
        return channel;
      } catch (error) {
        lastError = error;
        if (channel != null) {
          try {
            // A channel whose HTTP upgrade failed may never complete close().
            // Do not let cleanup prevent the next authorized ASR resource from
            // being attempted.
            unawaited(channel.sink.close().catchError((_) {}));
          } catch (_) {
            // The failed HTTP upgrade may already have closed the socket.
          }
        }
      }
    }
    throw StateError('ASR WebSocket handshake failed: $lastError');
  }

  List<({Uri endpoint, String resourceId})> _asrCandidates() {
    final configured = (
      endpoint: Uri.parse(settings.asrEndpoint),
      resourceId: settings.asrResourceId,
    );
    if (configured.endpoint.host != 'speech.bytedance.com') {
      return [configured];
    }
    const base = 'wss://speech.bytedance.com/api/v3/sauc/v2/';
    final standard = (
      endpoint: Uri.parse('${base}bigmodel_async'),
      resourceId: 'asr.streaming.model.big',
    );
    final twoPass = (
      endpoint: Uri.parse('${base}bigmodel_async_twopass'),
      resourceId: 'asr.streaming.model.big.twopass',
    );
    final fallback = configured.resourceId == twoPass.resourceId
        ? standard
        : twoPass;
    return [configured, if (fallback != configured) fallback];
  }

  Future<String> _readAsrResponses(Stream<Object?> responses) async {
    String? finalText;
    await for (final event in responses) {
      final frame = VolcSpeechProtocol.parse(_asBytes(event));
      if (frame.messageType == VolcSpeechProtocol.serverError) {
        throw _speechException(frame.payload, code: frame.errorCode);
      }
      if (frame.messageType != VolcSpeechProtocol.serverFullResponse) continue;
      final payload = VolcSpeechProtocol.decodeJsonPayload(frame.payload);
      if (!_isSuccessful(payload['code'], allowed: const [0])) {
        throw _speechException(frame.payload);
      }
      final result = _asrText(payload);
      if (_hasDefiniteResult(payload) && result != null && result.isNotEmpty) {
        finalText = result;
      }
      if (frame.isLast || payload['is_last_package'] == true) {
        finalText ??= result;
        if (finalText != null && finalText.isNotEmpty) return finalText;
        throw StateError('ASR returned no final result');
      }
    }
    if (finalText != null && finalText.isNotEmpty) return finalText;
    throw StateError('ASR returned no final result');
  }

  Future<String> chat(
    String prompt, {
    List<Map<String, String>> history = const [],
  }) async {
    final uri = joinArkUri(settings.arkBaseUrl, settings.arkChatPath);
    final response = await client
        .post(
          uri,
          headers: {
            if (settings.arkApiKey.isNotEmpty)
              'authorization': 'Bearer ${settings.arkApiKey}',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'model': settings.arkModel,
            'thinking': {'type': 'disabled'},
            'messages': [
              const {
                'role': 'system',
                'content':
                    '你是简洁、亲切的旅行导游。用适合语音播放的口语回答，默认用2到4句话、150到250字回答；用户要求详细时再展开。',
              },
              ...history,
              {'role': 'user', 'content': prompt},
            ],
            'max_tokens': 400,
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
      final message = (choices.first as Map)['message'];
      if (message is Map) content = message['content'];
    }
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('Chat response has no message');
    }
    return content.trim();
  }

  Future<String> structuredChat({
    required String systemPrompt,
    required String userPrompt,
    int maxTokens = 5000,
  }) async {
    final uri = joinArkUri(settings.arkBaseUrl, settings.arkChatPath);
    final response = await client
        .post(
          uri,
          headers: {
            if (settings.arkApiKey.isNotEmpty)
              'authorization': 'Bearer ${settings.arkApiKey}',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'model': settings.arkModel,
            'thinking': {'type': 'disabled'},
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user', 'content': userPrompt},
            ],
            'response_format': {'type': 'json_object'},
            'max_tokens': maxTokens,
            'temperature': 0.2,
          }),
        )
        .timeout(_structuredChatTimeout);
    if (response.bodyBytes.length > _maxTextBytes) {
      throw const HttpException('Structured response is too large');
    }
    _check(response.statusCode, response.bodyBytes);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final choices = decoded is Map ? decoded['choices'] : null;
    Object? content;
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final message = (choices.first as Map)['message'];
      if (message is Map) content = message['content'];
    }
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('Structured response has no message');
    }
    return content.trim();
  }

  Stream<String> chatStream(
    String prompt, {
    List<Map<String, String>> history = const [],
  }) async* {
    final request =
        http.Request(
            'POST',
            joinArkUri(settings.arkBaseUrl, settings.arkChatPath),
          )
          ..headers.addAll({
            if (settings.arkApiKey.isNotEmpty)
              'authorization': 'Bearer ${settings.arkApiKey}',
            'content-type': 'application/json',
            'accept': 'text/event-stream',
          })
          ..body = jsonEncode({
            'model': settings.arkModel,
            'stream': true,
            'thinking': {'type': 'disabled'},
            'messages': [
              const {
                'role': 'system',
                'content':
                    '你是简洁、亲切的旅行导游。用适合语音播放的口语回答，默认用2到4句话、150到250字回答；用户要求详细时再展开。',
              },
              ...history,
              {'role': 'user', 'content': prompt},
            ],
            'max_tokens': 400,
          });

    final response = await client.send(request).timeout(_chatIdleTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.toBytes();
      _check(response.statusCode, body);
    }

    var receivedContent = false;
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(_chatIdleTimeout);
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty || data == '[DONE]') continue;
      final decoded = jsonDecode(data);
      if (decoded is! Map) continue;
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty || choices.first is! Map) {
        continue;
      }
      final delta = (choices.first as Map)['delta'];
      if (delta is! Map) continue;
      final content = delta['content'];
      if (content is String && content.isNotEmpty) {
        receivedContent = true;
        for (final visualChunk in _visualChunks(content)) {
          yield visualChunk;
          // Ark or an intermediate proxy may place a whole paragraph in one
          // SSE content delta. Pace large deltas into paint-sized increments
          // so progressive rendering and sentence TTS do not depend on the
          // provider's network chunk boundaries.
          await Future<void>.delayed(const Duration(milliseconds: 24));
        }
      }
    }
    if (!receivedContent) {
      throw const FormatException('Chat stream returned no message');
    }
  }

  Future<Uint8List> synthesize(String text) async {
    if (settings.speechAccessKey.isNotEmpty &&
        settings.speechSecretKey.isNotEmpty &&
        settings.speechAppId.isNotEmpty) {
      return _synthesizeOverSailHttp(text);
    }

    final request = _jsonFrame({
      'app': {
        'appid': settings.speechAppId,
        'token': settings.speechToken,
        'cluster': settings.ttsCluster,
      },
      'user': {'uid': 'passport-user'},
      'audio': {
        'voice_type': settings.ttsVoice,
        'encoding': 'wav',
        'rate': 16000,
        'bits': 16,
        'channel': 1,
      },
      'request': {'reqid': _requestId(), 'text': text, 'operation': 'query'},
    });
    final channel = await websocket(Uri.parse(settings.ttsEndpoint), const {});
    final output = BytesBuilder(copy: false);
    try {
      channel.sink.add(request);
      await for (final event in channel.stream.timeout(_timeout)) {
        final frame = VolcSpeechProtocol.parse(_asBytes(event));
        if (frame.messageType == VolcSpeechProtocol.serverError) {
          throw _speechException(frame.payload);
        }
        if (frame.messageType == VolcSpeechProtocol.serverAudioOnly) {
          output.add(frame.payload);
        }
        if (frame.messageType == VolcSpeechProtocol.serverFullResponse) {
          final payload = VolcSpeechProtocol.decodeJsonPayload(frame.payload);
          if (!_isSuccessful(payload['code'], allowed: const [0, 3000])) {
            throw _speechException(frame.payload);
          }
          if (payload['data'] != null) {
            output.add(base64Decode(payload['data'] as String));
          }
          if (payload['is_last'] == true) return output.takeBytes();
        }
      }
      throw StateError('TTS returned no audio');
    } finally {
      await channel.sink.close();
    }
  }

  Future<Uint8List> _synthesizeOverSailHttp(String text) async {
    final token = await _getSailToken();
    final payload = jsonEncode({
      'text': text,
      'speaker': settings.ttsVoice,
      'audio_config': {'format': 'wav', 'sample_rate': 16000},
    });
    final requestBody = jsonEncode({
      'appkey': settings.speechAppId,
      'token': token,
      'namespace': 'TTS',
      'payload': payload,
    });
    late http.Response response;
    for (var attempt = 0; attempt < 2; attempt += 1) {
      response = await client
          .post(
            Uri.parse('https://sami.bytedance.com/internal/api/v1/invoke'),
            headers: {'content-type': 'application/json'},
            body: requestBody,
          )
          .timeout(_timeout);
      if (response.statusCode != 429 || attempt == 1) break;
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    _check(response.statusCode, response.bodyBytes);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map || decoded['status_code'] != 20000000) {
      throw StateError('SAMI TTS request failed: ${decoded?['status_text']}');
    }
    if (decoded['data'] is! String || (decoded['data'] as String).isEmpty) {
      throw StateError('SAMI TTS returned no audio');
    }

    final audio = base64Decode(decoded['data'] as String);
    if (audio.isEmpty) {
      throw StateError('SAMI TTS returned empty audio');
    }
    return Uint8List.fromList(audio);
  }

  Future<String> _getSailToken() async {
    final now = DateTime.now();
    if (_cachedSailToken != null &&
        _cachedSailTokenExpiresAt != null &&
        now.isBefore(_cachedSailTokenExpiresAt!)) {
      return _cachedSailToken!;
    }
    final pending = _pendingSailToken;
    if (pending != null) return pending;
    final request = _requestSailToken(now);
    _pendingSailToken = request;
    try {
      return await request;
    } finally {
      if (identical(_pendingSailToken, request)) _pendingSailToken = null;
    }
  }

  Future<String> _requestSailToken(DateTime now) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    const expiration = 86400;
    final signature = _sailTokenSigner.signature(
      accessKey: settings.speechAccessKey,
      secretKey: settings.speechSecretKey,
      timestamp: timestamp,
      expiration: expiration,
    );
    final uri = Uri.parse('https://sami.bytedance.com/internal/api/v1/token')
        .replace(
          queryParameters: {
            'version': 'auth-v1',
            'access_key': settings.speechAccessKey,
            'appkey': settings.speechAppId,
            'timestamp': '$timestamp',
            'expiration': '$expiration',
            'signature': signature,
          },
        );
    final response = await client.get(uri).timeout(_timeout);
    _check(response.statusCode, response.bodyBytes);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map || decoded['token'] is! String) {
      throw const FormatException('SAMI token response has no token');
    }
    _cachedSailToken = decoded['token'] as String;
    _cachedSailTokenExpiresAt = now.add(const Duration(hours: 23));
    return _cachedSailToken!;
  }

  void close() => client.close();

  Uint8List _jsonFrame(Map<String, Object?> value) => VolcSpeechProtocol.frame(
    VolcSpeechFrame(
      messageType: VolcSpeechProtocol.clientFullRequest,
      serialization: VolcSpeechProtocol.json,
      compression: VolcSpeechProtocol.noCompression,
      payload: Uint8List.fromList(utf8.encode(jsonEncode(value))),
    ),
  );

  Uint8List _asrConfigFrame(int sequence, Map<String, Object?> value) =>
      VolcSpeechProtocol.frame(
        VolcSpeechFrame(
          messageType: VolcSpeechProtocol.clientFullRequest,
          flags: VolcSpeechProtocol.positiveSequence,
          sequence: sequence,
          serialization: VolcSpeechProtocol.json,
          compression: VolcSpeechProtocol.gzip,
          payload: Uint8List.fromList(utf8.encode(jsonEncode(value))),
        ),
      );

  Uint8List _asrAudioFrame(
    int sequence,
    Uint8List payload, {
    required bool isLast,
  }) => VolcSpeechProtocol.frame(
    VolcSpeechFrame(
      messageType: VolcSpeechProtocol.clientAudioOnly,
      flags: isLast
          ? VolcSpeechProtocol.negativeWithSequence
          : VolcSpeechProtocol.positiveSequence,
      sequence: isLast ? -sequence : sequence,
      serialization: VolcSpeechProtocol.raw,
      compression: VolcSpeechProtocol.gzip,
      payload: payload,
    ),
  );

  Map<String, String> _sailHeaders(String connectId, String resourceId) => {
    'X-Api-App-Key': settings.speechAppId,
    'X-Api-Access-Key': settings.speechAccessKey,
    'X-Api-Resource-Id': resourceId,
    'X-Api-Connect-Id': connectId,
    'X-Api-Request-Id': connectId,
  };

  static String? _asrText(Map<String, Object?> payload) {
    final result = payload['result'];
    if (result is! Map) return null;
    final utterances = result['utterances'];
    if (utterances is List && utterances.isNotEmpty) {
      final parts = <String>[];
      for (final item in utterances) {
        if (item is Map && item['text'] is String) {
          parts.add(item['text'] as String);
        }
      }
      if (parts.isNotEmpty) return parts.join();
    }
    if (result['text'] is String) return result['text'] as String;
    return null;
  }

  static bool _isSuccessful(Object? code, {required List<int> allowed}) {
    return code == null || (code is int && allowed.contains(code));
  }

  static bool _hasDefiniteResult(Map<String, Object?> payload) {
    final result = payload['result'];
    if (result is! Map) return false;
    final utterances = result['utterances'];
    return utterances is List &&
        utterances.any((item) => item is Map && item['definite'] == true);
  }

  static Uri joinArkUri(String baseUrl, String chatPath) {
    final base = Uri.parse(baseUrl);
    final normalizedPath = chatPath.startsWith('/') ? chatPath : '/$chatPath';
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(path: '$basePath$normalizedPath');
  }

  static Iterable<String> _visualChunks(String content) sync* {
    final runes = content.runes.toList(growable: false);
    if (runes.length <= 8) {
      yield content;
      return;
    }
    const runesPerFrame = 4;
    for (var offset = 0; offset < runes.length; offset += runesPerFrame) {
      final end = (offset + runesPerFrame).clamp(0, runes.length);
      yield String.fromCharCodes(runes.sublist(offset, end));
    }
  }

  static Object _speechException(Uint8List payload, {int? code}) {
    final text = utf8.decode(payload, allowMalformed: true);
    final prefix = code == null ? '' : ' $code';
    return StateError('Volcengine speech error$prefix: $text');
  }

  static Uint8List _asBytes(Object? event) {
    if (event is Uint8List) return event;
    if (event is List<int>) return Uint8List.fromList(event);
    if (event is String) return Uint8List.fromList(utf8.encode(event));
    throw const FormatException('WebSocket event is not binary');
  }

  static String _requestId() {
    final milliseconds = DateTime.now().microsecondsSinceEpoch.toRadixString(
      16,
    );
    return 'passport-$milliseconds';
  }

  static String _connectId() {
    final random = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return 'passport-$random';
  }

  static Future<WebSocketChannel> _connectWebsocketWithHeaders(
    Uri uri,
    Map<String, String> headers,
  ) async => IOWebSocketChannel.connect(uri, headers: headers);

  static void _check(int status, Uint8List body) {
    if (status >= 200 && status < 300) return;
    final detail = utf8.decode(body.take(240).toList(), allowMalformed: true);
    throw HttpException('HTTP $status: $detail');
  }
}

typedef WebSocketFactory = Future<WebSocketChannel> Function(
  Uri uri,
  Map<String, String> headers,
);

final class HttpException implements Exception {
  const HttpException(this.message);
  final String message;

  @override
  String toString() => message;
}
