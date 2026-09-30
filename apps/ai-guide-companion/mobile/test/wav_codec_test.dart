import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guide_companion/audio/wav_codec.dart';
import 'package:guide_companion/protocol/ima_adpcm.dart';

void main() {
  test('accepts the required 16 kHz mono PCM WAV format', () {
    final source = Int16List.fromList([0, 1200, -1200, 32767, -32768]);
    final bytes = ImaAdpcm.pcm16Wave([source], 16000);
    final wave = WavCodec.decodeMonoPcm16(bytes);

    expect(wave.sampleRate, 16000);
    expect(wave.samples, source);
  });

  test('rejects unsupported TTS sample rates', () {
    final bytes = ImaAdpcm.pcm16Wave([Int16List(8)], 24000);
    expect(
      () => WavCodec.decodeMonoPcm16(bytes),
      throwsA(isA<FormatException>()),
    );
  });

  test('accepts a streaming WAV whose data length is left open-ended', () {
    final source = Int16List.fromList([0, 1200, -1200, 32767, -32768]);
    final bytes = ImaAdpcm.pcm16Wave([source], 16000);
    ByteData.sublistView(bytes).setUint32(40, 0x7fffffff, Endian.little);

    final wave = WavCodec.decodeMonoPcm16(bytes);

    expect(wave.sampleRate, 16000);
    expect(wave.samples, source);
  });
}
