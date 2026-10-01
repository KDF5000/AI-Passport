import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class AiSettings {
  static const defaultArkModel = '';
  static const defaultArkBaseUrl = 'https://ark.cn-beijing.volces.com/api/v3';
  static const defaultArkChatPath = '/chat/completions';
  static const defaultArkEndpoint = '$defaultArkBaseUrl$defaultArkChatPath';
  static const defaultSailVoice = 'zh_female_qingxin';
  static const defaultAsrEndpoint =
      'wss://speech.bytedance.com/api/v3/sauc/v2/bigmodel_async';
  static const defaultTtsEndpoint =
      'https://sami.bytedance.com/internal/api/v1/invoke';
  static const legacyTtsWebSocketEndpoint =
      'wss://openspeech.bytedance.com/api/v1/tts/ws_binary';
  static const internalAsrHost = 'speech.byted.org';
  static const externalAsrHost = 'speech.bytedance.com';

  const AiSettings({
    this.arkBaseUrl = defaultArkBaseUrl,
    this.arkChatPath = defaultArkChatPath,
    this.arkModel = defaultArkModel,
    this.arkApiKey = '',
    this.speechAppId = '',
    this.speechAccessKey = '',
    this.speechSecretKey = '',
    this.speechToken = '',
    this.asrEndpoint = defaultAsrEndpoint,
    this.asrResourceId = 'asr.streaming.model.big',
    this.asrCluster = '',
    this.ttsEndpoint = defaultTtsEndpoint,
    this.ttsCluster = 'volcano_tts',
    this.ttsVoice = defaultSailVoice,
  });

  final String arkBaseUrl;
  final String arkChatPath;
  final String arkModel;
  final String arkApiKey;
  final String speechAppId;
  final String speechAccessKey;
  final String speechSecretKey;
  final String speechToken;
  final String asrEndpoint;
  final String asrResourceId;
  final String asrCluster;
  final String ttsEndpoint;
  final String ttsCluster;
  final String ttsVoice;

  String get arkEndpoint {
    if (arkChatPath.trim().isEmpty) return arkBaseUrl;
    final base = Uri.parse(arkBaseUrl);
    final path = arkChatPath.startsWith('/') ? arkChatPath : '/$arkChatPath';
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(path: '$basePath$path').toString();
  }

  static String normalizeAsrEndpoint(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) {
      return defaultAsrEndpoint;
    }
    final endpoint = Uri.tryParse(raw);
    if (endpoint == null || endpoint.host.isEmpty) return defaultAsrEndpoint;
    if (endpoint.host == internalAsrHost || endpoint.host == externalAsrHost) {
      final path = endpoint.path.endsWith('/bigmodel_async_twopass')
          ? '/api/v3/sauc/v2/bigmodel_async_twopass'
          : '/api/v3/sauc/v2/bigmodel_async';
      return Uri(scheme: 'wss', host: externalAsrHost, path: path).toString();
    }
    if (endpoint.scheme != 'wss' && endpoint.scheme != 'ws') {
      return defaultAsrEndpoint;
    }
    return Uri(
      scheme: endpoint.scheme,
      userInfo: endpoint.userInfo,
      host: endpoint.host,
      port: endpoint.hasPort ? endpoint.port : null,
      path: endpoint.path,
      query: endpoint.hasQuery ? endpoint.query : null,
    ).toString();
  }

  static String normalizeTtsEndpoint(String? value) {
    final endpoint = value?.trim();
    if (endpoint == null ||
        endpoint.isEmpty ||
        endpoint == legacyTtsWebSocketEndpoint) {
      return defaultTtsEndpoint;
    }
    return endpoint;
  }

  AiSettings copyWith({
    String? arkBaseUrl,
    String? arkChatPath,
    String? arkModel,
    String? arkApiKey,
    String? speechAppId,
    String? speechAccessKey,
    String? speechSecretKey,
    String? speechToken,
    String? asrEndpoint,
    String? asrResourceId,
    String? asrCluster,
    String? ttsEndpoint,
    String? ttsCluster,
    String? ttsVoice,
  }) => AiSettings(
    arkBaseUrl: arkBaseUrl ?? this.arkBaseUrl,
    arkChatPath: arkChatPath ?? this.arkChatPath,
    arkModel: arkModel ?? this.arkModel,
    arkApiKey: arkApiKey ?? this.arkApiKey,
    speechAppId: speechAppId ?? this.speechAppId,
    speechAccessKey: speechAccessKey ?? this.speechAccessKey,
    speechSecretKey: speechSecretKey ?? this.speechSecretKey,
    speechToken: speechToken ?? this.speechToken,
    asrEndpoint: asrEndpoint ?? this.asrEndpoint,
    asrResourceId: asrResourceId ?? this.asrResourceId,
    asrCluster: asrCluster ?? this.asrCluster,
    ttsEndpoint: ttsEndpoint ?? this.ttsEndpoint,
    ttsCluster: ttsCluster ?? this.ttsCluster,
    ttsVoice: ttsVoice ?? this.ttsVoice,
  );
}

final class AiSettingsStore {
  static const _secret = FlutterSecureStorage();

  Future<AiSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final secrets = await Future.wait<String?>([
      _secret.read(key: 'arkApiKey'),
      _secret.read(key: 'speechAccessKey'),
      _secret.read(key: 'speechSecretKey'),
      _secret.read(key: 'speechToken'),
    ]);
    return AiSettings(
      arkBaseUrl: prefs.getString('arkBaseUrl') ?? AiSettings.defaultArkBaseUrl,
      arkChatPath:
          prefs.getString('arkChatPath') ?? AiSettings.defaultArkChatPath,
      arkModel: prefs.getString('arkModel') ?? AiSettings.defaultArkModel,
      arkApiKey: secrets[0] ?? '',
      speechAppId: prefs.getString('speechAppId') ?? '',
      speechAccessKey: secrets[1] ?? '',
      speechSecretKey: secrets[2] ?? '',
      speechToken: secrets[3] ?? '',
      asrEndpoint: AiSettings.normalizeAsrEndpoint(
        prefs.getString('asrEndpoint'),
      ),
      asrResourceId:
          prefs.getString('asrResourceId') ?? 'asr.streaming.model.big',
      asrCluster: prefs.getString('asrCluster') ?? '',
      ttsEndpoint: AiSettings.normalizeTtsEndpoint(
        prefs.getString('ttsEndpoint'),
      ),
      ttsCluster: prefs.getString('ttsCluster') ?? 'volcano_tts',
      ttsVoice: prefs.getString('ttsVoice') == 'BV700_V2_streaming'
          ? AiSettings.defaultSailVoice
          : prefs.getString('ttsVoice') ?? AiSettings.defaultSailVoice,
    );
  }

  Future<void> save(AiSettings value) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString('arkBaseUrl', value.arkBaseUrl),
      prefs.setString('arkChatPath', value.arkChatPath),
      prefs.setString('arkModel', value.arkModel),
      prefs.setString('speechAppId', value.speechAppId),
      prefs.setString(
        'asrEndpoint',
        AiSettings.normalizeAsrEndpoint(value.asrEndpoint),
      ),
      prefs.setString('asrResourceId', value.asrResourceId),
      prefs.setString('asrCluster', value.asrCluster),
      prefs.setString(
        'ttsEndpoint',
        AiSettings.normalizeTtsEndpoint(value.ttsEndpoint),
      ),
      prefs.setString('ttsCluster', value.ttsCluster),
      prefs.setString('ttsVoice', value.ttsVoice),
      _secret.write(key: 'arkApiKey', value: value.arkApiKey),
      _secret.write(key: 'speechAccessKey', value: value.speechAccessKey),
      _secret.write(key: 'speechSecretKey', value: value.speechSecretKey),
      _secret.write(key: 'speechToken', value: value.speechToken),
    ]);
  }
}
