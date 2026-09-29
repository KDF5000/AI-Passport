import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'ai/ai_gateway.dart';
import 'ai/ai_settings.dart';
import 'audio/wav_codec.dart';
import 'ble/guide_ble_session.dart';
import 'protocol/guide_protocol.dart';
import 'protocol/ima_adpcm.dart';

final class GuideController extends ChangeNotifier {
  GuideController({AiSettingsStore? store})
    : store = store ?? AiSettingsStore() {
    ble = GuideBleSession(onPacket: _onPacket, onState: _onBleState);
  }

  final AiSettingsStore store;
  late final GuideBleSession ble;
  AiSettings settings = const AiSettings();
  GuideConnectionState connection = GuideConnectionState.disconnected;
  String status = 'Load settings, then connect your Passport';
  String transcript = '';
  String answer = '';
  bool busy = false;
  final List<Int16List> _recording = [];
  final List<Map<String, String>> _history = [];
  int _sampleRate = 16000;
  bool _disposed = false;

  Future<void> load() async {
    settings = await store.load();
    notifyListeners();
  }

  Future<void> saveSettings(AiSettings value) async {
    settings = value;
    await store.save(value);
    status = 'Settings saved';
    notifyListeners();
  }

  Future<void> connect() async {
    try {
      await ble.connect();
    } catch (error) {
      status = 'Bluetooth error: $error';
      connection = GuideConnectionState.disconnected;
      notifyListeners();
      await ble.disconnect();
    }
  }

  void _onBleState(GuideConnectionState value, String detail) {
    if (_disposed) return;
    connection = value;
    status = detail;
    notifyListeners();
  }

  void _onPacket(Uint8List packet) {
    if (_disposed || packet.isEmpty) return;
    switch (packet.first) {
      case GuidePacketType.recordingStart:
        if (packet.length >= 3) {
          _sampleRate = packet[1] | (packet[2] << 8);
        }
        _recording.clear();
        transcript = '';
        answer = '';
        status = 'Listening…';
        notifyListeners();
      case GuidePacketType.recordingAudio:
        final decoded = ImaAdpcm.decode(Uint8List.sublistView(packet, 1));
        if (decoded.isNotEmpty) {
          _recording.add(
            Int16List.sublistView(decoded, 0, decoded.length.clamp(0, 320)),
          );
        }
      case GuidePacketType.recordingEnd:
        unawaited(_processRecording());
      case GuidePacketType.error:
        status = String.fromCharCodes(packet.skip(1));
        notifyListeners();
    }
  }

  Future<void> _processRecording() async {
    if (busy || _recording.isEmpty) return;
    busy = true;
    status = 'Transcribing…';
    notifyListeners();
    final gateway = AiGateway(settings);
    try {
      final wav = ImaAdpcm.pcm16Wave(_recording, _sampleRate);
      transcript = await gateway.transcribe(wav);
      await ble.sendText(GuidePacketType.transcript, transcript);
      status = 'Asking AI…';
      notifyListeners();

      answer = await gateway.chat(transcript, history: _history);
      _history
        ..add({'role': 'user', 'content': transcript})
        ..add({'role': 'assistant', 'content': answer});
      if (_history.length > 8) _history.removeRange(0, _history.length - 8);
      await ble.sendText(GuidePacketType.answerText, answer);
      status = 'Creating voice…';
      notifyListeners();

      final wave = WavCodec.decodeMonoPcm16(await gateway.synthesize(answer));
      await ble.send(GuidePacketType.playbackStart, [
        wave.sampleRate & 0xff,
        wave.sampleRate >> 8,
      ]);
      for (var offset = 0; offset < wave.samples.length; offset += 320) {
        final end = (offset + 320).clamp(0, wave.samples.length);
        final chunk = Int16List(320);
        chunk.setRange(0, end - offset, wave.samples, offset);
        await ble.send(GuidePacketType.playbackAudio, ImaAdpcm.encode(chunk));
      }
      await ble.send(GuidePacketType.responseEnd);
      status = 'Ready · hold OK to ask again';
    } catch (error) {
      status = 'Request failed: $error';
      try {
        await ble.sendText(GuidePacketType.error, status);
      } catch (_) {
        // Preserve the original request error when BLE also disconnected.
      }
    } finally {
      _recording.clear();
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(ble.disconnect());
    super.dispose();
  }
}
