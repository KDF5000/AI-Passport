import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class AiSettings {
  const AiSettings({
    this.baseUrl = '',
    this.sttPath = '/v1/audio/transcriptions',
    this.chatPath = '/v1/chat/completions',
    this.ttsPath = '/v1/audio/speech',
    this.chatModel = '',
    this.sttModel = 'whisper-1',
    this.ttsModel = '',
    this.voice = 'alloy',
    this.apiKey = '',
  });

  final String baseUrl;
  final String sttPath;
  final String chatPath;
  final String ttsPath;
  final String chatModel;
  final String sttModel;
  final String ttsModel;
  final String voice;
  final String apiKey;

  AiSettings copyWith({
    String? baseUrl,
    String? sttPath,
    String? chatPath,
    String? ttsPath,
    String? chatModel,
    String? sttModel,
    String? ttsModel,
    String? voice,
    String? apiKey,
  }) => AiSettings(
    baseUrl: baseUrl ?? this.baseUrl,
    sttPath: sttPath ?? this.sttPath,
    chatPath: chatPath ?? this.chatPath,
    ttsPath: ttsPath ?? this.ttsPath,
    chatModel: chatModel ?? this.chatModel,
    sttModel: sttModel ?? this.sttModel,
    ttsModel: ttsModel ?? this.ttsModel,
    voice: voice ?? this.voice,
    apiKey: apiKey ?? this.apiKey,
  );
}

final class AiSettingsStore {
  static const _secret = FlutterSecureStorage();

  Future<AiSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AiSettings(
      baseUrl: prefs.getString('baseUrl') ?? '',
      sttPath: prefs.getString('sttPath') ?? '/v1/audio/transcriptions',
      chatPath: prefs.getString('chatPath') ?? '/v1/chat/completions',
      ttsPath: prefs.getString('ttsPath') ?? '/v1/audio/speech',
      chatModel: prefs.getString('chatModel') ?? '',
      sttModel: prefs.getString('sttModel') ?? 'whisper-1',
      ttsModel: prefs.getString('ttsModel') ?? '',
      voice: prefs.getString('voice') ?? 'alloy',
      apiKey: await _secret.read(key: 'apiKey') ?? '',
    );
  }

  Future<void> save(AiSettings value) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString('baseUrl', value.baseUrl),
      prefs.setString('sttPath', value.sttPath),
      prefs.setString('chatPath', value.chatPath),
      prefs.setString('ttsPath', value.ttsPath),
      prefs.setString('chatModel', value.chatModel),
      prefs.setString('sttModel', value.sttModel),
      prefs.setString('ttsModel', value.ttsModel),
      prefs.setString('voice', value.voice),
      _secret.write(key: 'apiKey', value: value.apiKey),
    ]);
  }
}
