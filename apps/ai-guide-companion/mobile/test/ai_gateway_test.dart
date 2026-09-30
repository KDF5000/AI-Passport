import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guide_companion/ai/ai_gateway.dart';
import 'package:guide_companion/ai/ai_settings.dart';
import 'package:guide_companion/ai/volc_speech_protocol.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('does not ship a personal Ark endpoint', () {
    expect(const AiSettings().arkModel, isEmpty);
  });

  const settings = AiSettings(
    arkBaseUrl: 'https://example.test/api/v3',
    arkChatPath: '/chat/completions',
    arkModel: 'guide-model',
    arkApiKey: 'test-only',
  );
  const sailSettings = AiSettings(
    speechAppId: 'app-test',
    speechAccessKey: 'ak-test',
    speechSecretKey: 'sk-test',
    ttsVoice: 'zh_female_qingxin',
  );

  test('parses an Ark chat response', () async {
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://example.test/api/v3/chat/completions',
      );
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

  test('requests strict JSON for structured trip generation', () async {
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['response_format'], {'type': 'json_object'});
      expect(body['temperature'], 0.2);
      expect(body['max_tokens'], 5000);
      expect((body['messages'] as List).first['content'], 'system rules');
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': '{"title":"route"}'},
            },
          ],
        }),
        200,
      );
    });

    final result = await AiGateway(
      settings,
      client: client,
    ).structuredChat(systemPrompt: 'system rules', userPrompt: 'trip input');

    expect(result, '{"title":"route"}');
  });

  test('streams Ark chat deltas', () async {
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['stream'], isTrue);
      expect(body['max_tokens'], 400);
      expect(body['thinking'], {'type': 'disabled'});
      return http.Response.bytes(
        utf8.encode(
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': '先去主剧场。'},
              },
            ],
          })}\n\n'
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': '再看幻城剧场。'},
              },
            ],
          })}\n\n'
          'data: [DONE]\n\n',
        ),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });

    final chunks = await AiGateway(
      settings,
      client: client,
    ).chatStream('怎么玩？').toList();

    expect(chunks, ['先去主剧场。', '再看幻城剧场。']);
  });

  test('paces a provider-buffered paragraph into visual chunks', () async {
    final client = MockClient((_) async {
      final event = jsonEncode({
        'choices': [
          {
            'delta': {'content': '天津适合慢慢逛，也适合沿河散步。'},
          },
        ],
      });
      return http.Response.bytes(
        utf8.encode('data: $event\n\ndata: [DONE]\n\n'),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });

    final chunks = await AiGateway(
      settings,
      client: client,
    ).chatStream('天津怎么玩？').toList();

    expect(chunks.length, greaterThan(1));
    expect(chunks.join(), '天津适合慢慢逛，也适合沿河散步。');
    expect(chunks.every((chunk) => chunk.runes.length <= 4), isTrue);
  });

  test('surfaces Ark HTTP errors', () {
    final client = MockClient(
      (_) async => http.Response('service unavailable', 503),
    );

    expect(
      AiGateway(settings, client: client).chat('Hello'),
      throwsA(isA<HttpException>()),
    );
  });

  test('gets a SAIL token and synthesizes audio over HTTP', () async {
    var tokenRequested = false;
    final client = MockClient((request) async {
      if (!tokenRequested) {
        tokenRequested = true;
        expect(request.url.host, 'sami.bytedance.com');
        expect(request.url.path, '/internal/api/v1/token');
        expect(request.url.queryParameters['appkey'], 'app-test');
        return http.Response(jsonEncode({'token': 'sail-token'}), 200);
      }
      expect(request.url.path, '/internal/api/v1/invoke');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['namespace'], 'TTS');
      final payload =
          jsonDecode(body['payload'] as String) as Map<String, dynamic>;
      expect(payload['audio_config'], {'format': 'wav', 'sample_rate': 16000});
      return http.Response(
        jsonEncode({
          'status_code': 20000000,
          'data': base64Encode(utf8.encode('RIFFWAV')),
        }),
        200,
      );
    });

    final audio = await AiGateway(
      sailSettings,
      client: client,
    ).synthesize('Hello');

    expect(audio, utf8.encode('RIFFWAV'));
  });

  test('retries a rate-limited SAIL TTS request once', () async {
    var tokenRequested = false;
    var synthesisRequests = 0;
    final client = MockClient((request) async {
      if (!tokenRequested) {
        tokenRequested = true;
        return http.Response(jsonEncode({'token': 'sail-token'}), 200);
      }
      synthesisRequests += 1;
      if (synthesisRequests == 1) {
        return http.Response(
          jsonEncode({
            'status_code': 40200011,
            'status_text': 'ExceededQPSQuota',
            'namespace': 'TTS',
          }),
          429,
        );
      }
      return http.Response(
        jsonEncode({
          'status_code': 20000000,
          'data': base64Encode(utf8.encode('RIFFWAV')),
        }),
        200,
      );
    });

    final audio = await AiGateway(
      sailSettings,
      client: client,
    ).synthesize('Hello');

    expect(synthesisRequests, 2);
    expect(audio, utf8.encode('RIFFWAV'));
  });

  test('transcribes PCM through SAIL v3 two-pass ASR', () async {
    final pcm = Uint8List.fromList(List<int>.filled(3200, 1));
    Uri? connectedUri;
    Map<String, String>? connectedHeaders;
    final sent = <Uint8List>[];
    final outgoing = StreamController<List<int>>();
    final incoming = StreamController<List<int>>();
    addTearDown(() async {
      if (!outgoing.isClosed) await outgoing.close();
      if (!incoming.isClosed) await incoming.close();
    });
    final channel = _FakeBinaryWebSocketChannel(
      stream: incoming.stream,
      sink: outgoing.sink,
    );
    outgoing.stream.listen((event) {
      sent.add(Uint8List.fromList(event));
      if (sent.length == 2) {
        scheduleMicrotask(() {
          incoming.add(
            _fullResponse({
              'is_last_package': true,
              'result': {
                'text': '你好，河南。',
                'utterances': [
                  {'text': '你好，河南。', 'definite': true},
                ],
              },
            }),
          );
        });
      }
    });

    final gateway = AiGateway(
      sailSettings.copyWith(
        asrEndpoint:
            'wss://speech.example.test/api/v3/sauc/v2/bigmodel_async_twopass',
        asrResourceId: 'asr.streaming.model.big.twopass',
      ),
      websocket: (uri, headers) async {
        connectedUri = uri;
        connectedHeaders = Map<String, String>.from(headers);
        return channel;
      },
    );

    final transcript = await gateway.transcribePcm(pcm);

    expect(transcript, '你好，河南。');
    expect(connectedUri.toString(), contains('bigmodel_async_twopass'));
    expect(connectedHeaders?['X-Api-App-Key'], 'app-test');
    expect(connectedHeaders?['X-Api-Access-Key'], 'ak-test');
    expect(
      connectedHeaders?['X-Api-Resource-Id'],
      'asr.streaming.model.big.twopass',
    );
    expect(connectedHeaders?.containsKey('X-Api-Connect-Id'), isTrue);
    expect(connectedHeaders?.containsKey('X-Api-Request-Id'), isTrue);
    expect(sent.length, 2);
    final first = VolcSpeechProtocol.parse(sent.first);
    final config =
        jsonDecode(utf8.decode(first.payload)) as Map<String, dynamic>;
    expect(first.sequence, 1);
    expect(first.compression, VolcSpeechProtocol.gzip);
    expect(config['audio'], {
      'format': 'pcm',
      'rate': 16000,
      'bits': 16,
      'channel': 1,
    });
    final last = VolcSpeechProtocol.parse(sent.last);
    expect(last.messageType, VolcSpeechProtocol.clientAudioOnly);
    expect(last.sequence, -2);
    expect(last.isLast, isTrue);
    expect(last.payload.length, 3200);
  });
}

final class _FakeBinaryWebSocketChannel implements WebSocketChannel {
  _FakeBinaryWebSocketChannel({
    required this.stream,
    required StreamSink<List<int>> sink,
  }) : sink = _DelegatingWebSocketSink(sink);

  @override
  final Stream<List<int>> stream;
  @override
  final WebSocketSink sink;
  @override
  Future<void> get ready => Future.value();
  @override
  String? protocol;
  @override
  int? closeCode;
  @override
  String? closeReason;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _DelegatingWebSocketSink implements WebSocketSink {
  const _DelegatingWebSocketSink(this.delegate);

  final StreamSink<List<int>> delegate;

  @override
  void add(Object? event) => delegate.add(event as List<int>);

  @override
  Future<void> close([int? closeCode, String? closeReason]) => delegate.close();

  @override
  Future<void> get done => delegate.done;

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      delegate.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<Object?> stream) =>
      delegate.addStream(stream.cast<List<int>>());
}

List<int> _fullResponse(Map<String, Object?> payload) =>
    VolcSpeechProtocol.frame(
      VolcSpeechFrame(
        messageType: VolcSpeechProtocol.serverFullResponse,
        serialization: VolcSpeechProtocol.json,
        compression: VolcSpeechProtocol.noCompression,
        payload: Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      ),
    );
