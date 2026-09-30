import 'dart:typed_data';

final class PcmWave {
  const PcmWave({required this.sampleRate, required this.samples});

  final int sampleRate;
  final Int16List samples;
}

abstract final class WavCodec {
  static PcmWave decodeMonoPcm16(Uint8List bytes) {
    if (bytes.length < 44 ||
        _ascii(bytes, 0, 4) != 'RIFF' ||
        _ascii(bytes, 8, 4) != 'WAVE') {
      throw const FormatException('TTS response is not a WAV file');
    }

    final data = ByteData.sublistView(bytes);
    int? sampleRate;
    int? dataOffset;
    int? dataLength;
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final id = _ascii(bytes, offset, 4);
      final size = data.getUint32(offset + 4, Endian.little);
      final payload = offset + 8;
      if (id == 'data') {
        // Some streaming TTS services emit a WAV header before the final audio
        // length is known and leave the data size at 0x7fffffff/0xffffffff.
        // The response body is complete here, so its remaining bytes are the
        // authoritative PCM length. Do not walk PCM as if it contained chunks.
        dataOffset = payload;
        dataLength = size.clamp(0, bytes.length - payload);
        break;
      }
      if (payload + size > bytes.length) {
        throw const FormatException('Truncated WAV chunk');
      }
      if (id == 'fmt ') {
        if (size < 16 ||
            data.getUint16(payload, Endian.little) != 1 ||
            data.getUint16(payload + 2, Endian.little) != 1 ||
            data.getUint16(payload + 14, Endian.little) != 16) {
          throw const FormatException('TTS must return mono 16-bit PCM WAV');
        }
        sampleRate = data.getUint32(payload + 4, Endian.little);
      }
      offset = payload + size + (size.isOdd ? 1 : 0);
    }

    if (sampleRate == null || dataOffset == null || dataLength == null) {
      throw const FormatException('WAV is missing fmt or data');
    }
    if (sampleRate != 16000 || dataLength.isOdd) {
      throw const FormatException('TTS must return 16 kHz mono PCM WAV');
    }
    final samples = Int16List(dataLength ~/ 2);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = data.getInt16(dataOffset + i * 2, Endian.little);
    }
    return PcmWave(sampleRate: sampleRate, samples: samples);
  }

  static String _ascii(Uint8List bytes, int offset, int length) =>
      String.fromCharCodes(bytes.sublist(offset, offset + length));
}
