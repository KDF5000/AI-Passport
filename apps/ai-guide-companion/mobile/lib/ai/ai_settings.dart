import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class AiSettings {
  static const defaultArkModel = '';
  static const defaultSailVoice = 'zh_female_qingxin';

  const AiSettings({
    this.arkBaseUrl = 'https://ark.cn-beijing.volces.com/api/v3',
    this.arkChatPath = '/chat/completions',
    this.arkModel = defaultArkModel,
    this.arkApiKey = '',
    this.speechAppId = '',
    this.speechAccessKey = '',
    this.speechSecretKey = '',
    this.speechToken = '',
    this.asrEndpoint =
        'wss://speech.bytedance.com/api/v3/sauc/v2/bigmodel_async',
    this.asrResourceId = 'asr.streaming.model.big',
    this.asrCluster = '',
    this.ttsEndpoint = 'wss://openspeech.bytedance.com/api/v1/tts/ws_binary',
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
      arkBaseUrl:
          prefs.getString('arkBaseUrl') ??
          'https://ark.cn-beijing.volces.com/api/v3',
      arkChatPath: prefs.getString('arkChatPath') ?? '/chat/completions',
      arkModel: prefs.getString('arkModel') ?? AiSettings.defaultArkModel,
      arkApiKey: secrets[0] ?? '',
      speechAppId: prefs.getString('speechAppId') ?? '',
      speechAccessKey: secrets[1] ?? '',
      speechSecretKey: secrets[2] ?? '',
      speechToken: secrets[3] ?? '',
      asrEndpoint:
          prefs.getString('asrEndpoint') ??
          'wss://speech.bytedance.com/api/v3/sauc/v2/bigmodel_async',
      asrResourceId:
          prefs.getString('asrResourceId') ?? 'asr.streaming.model.big',
      asrCluster: prefs.getString('asrCluster') ?? '',
      ttsEndpoint:
          prefs.getString('ttsEndpoint') ??
          'wss://openspeech.bytedance.com/api/v1/tts/ws_binary',
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
      prefs.setString('asrEndpoint', value.asrEndpoint),
      prefs.setString('asrResourceId', value.asrResourceId),
      prefs.setString('asrCluster', value.asrCluster),
      prefs.setString('ttsEndpoint', value.ttsEndpoint),
      prefs.setString('ttsCluster', value.ttsCluster),
      prefs.setString('ttsVoice', value.ttsVoice),
      _secret.write(key: 'arkApiKey', value: value.arkApiKey),
      _secret.write(key: 'speechAccessKey', value: value.speechAccessKey),
      _secret.write(key: 'speechSecretKey', value: value.speechSecretKey),
      _secret.write(key: 'speechToken', value: value.speechToken),
    ]);
  }
}
