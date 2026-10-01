import 'dart:typed_data';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'wav_codec.dart';

class MobileVoice {
  MobileVoice({AudioRecorder? recorder, AudioPlayer? player})
    : _recorder = recorder ?? AudioRecorder(),
      _player = player ?? AudioPlayer();

  final AudioRecorder _recorder;
  final AudioPlayer _player;
  String? _recordingPath;

  Future<bool> ensurePermission() => _recorder.hasPermission();

  Future<void> startRecording() async {
    final directory = await getTemporaryDirectory();
    _recordingPath = '${directory.path}/guide-question.wav';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 256000,
      ),
      path: _recordingPath!,
    );
  }

  Future<Uint8List> stopRecordingPcm() async {
    final path = await _recorder.stop();
    final file = File(path ?? _recordingPath!);
    final bytes = await file.readAsBytes();
    final wave = WavCodec.decodeMonoPcm16(Uint8List.fromList(bytes));
    final pcm = Uint8List(wave.samples.length * 2);
    final data = ByteData.sublistView(pcm);
    for (var i = 0; i < wave.samples.length; i++) {
      data.setInt16(i * 2, wave.samples[i], Endian.little);
    }
    return pcm;
  }

  Future<void> playWavAndWait(Uint8List audio) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/guide-answer.wav');
    await file.writeAsBytes(audio, flush: true);
    await _player.stop();
    final completed = _player.onPlayerComplete.first;
    await _player.play(DeviceFileSource(file.path));
    await completed.timeout(const Duration(minutes: 2));
  }

  Future<void> stopPlayback() => _player.stop();

  Future<void> dispose() async {
    await _recorder.dispose();
    await _player.dispose();
  }
}
