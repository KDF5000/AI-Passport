import 'dart:math' as math;
import 'dart:typed_data';

abstract final class ImaAdpcm {
  static const headerBytes = 4;
  static const _steps = <int>[
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    16,
    17,
    19,
    21,
    23,
    25,
    28,
    31,
    34,
    37,
    41,
    45,
    50,
    55,
    60,
    66,
    73,
    80,
    88,
    97,
    107,
    118,
    130,
    143,
    157,
    173,
    190,
    209,
    230,
    253,
    279,
    307,
    337,
    371,
    408,
    449,
    494,
    544,
    598,
    658,
    724,
    796,
    876,
    963,
    1060,
    1166,
    1282,
    1411,
    1552,
    1707,
    1878,
    2066,
    2272,
    2499,
    2749,
    3024,
    3327,
    3660,
    4026,
    4428,
    4871,
    5358,
    5894,
    6484,
    7132,
    7845,
    8630,
    9493,
    10442,
    11487,
    12635,
    13899,
    15289,
    16818,
    18500,
    20350,
    22385,
    24623,
    27086,
    29794,
    32767,
  ];
  static const _indexes = <int>[
    -1,
    -1,
    -1,
    -1,
    2,
    4,
    6,
    8,
    -1,
    -1,
    -1,
    -1,
    2,
    4,
    6,
    8,
  ];

  static Uint8List encode(Int16List pcm) {
    return ImaAdpcmEncoder().encode(pcm);
  }

  static Int16List decode(Uint8List block) {
    if (block.length < headerBytes || block[2] > 88) return Int16List(0);
    final data = ByteData.sublistView(block);
    var predictor = data.getInt16(0, Endian.little);
    var index = block[2];
    final result = Int16List(1 + (block.length - headerBytes) * 2);
    result[0] = predictor;
    var outputIndex = 1;

    for (var i = headerBytes; i < block.length; i++) {
      for (final code in [block[i] & 0x0f, block[i] >> 4]) {
        final step = _steps[index];
        var delta = step >> 3;
        if ((code & 4) != 0) delta += step;
        if ((code & 2) != 0) delta += step >> 1;
        if ((code & 1) != 0) delta += step >> 2;
        predictor = math.max(
          -32768,
          math.min(32767, predictor + ((code & 8) != 0 ? -delta : delta)),
        );
        index = math.max(0, math.min(88, index + _indexes[code]));
        result[outputIndex++] = predictor;
      }
    }
    return result;
  }

  static Uint8List pcm16Wave(Iterable<Int16List> blocks, int sampleRate) {
    final samples = blocks.fold<int>(0, (sum, block) => sum + block.length);
    final out = Uint8List(44 + samples * 2);
    final data = ByteData.sublistView(out);
    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        out[offset + i] = value.codeUnitAt(i);
      }
    }

    ascii(0, 'RIFF');
    data.setUint32(4, out.length - 8, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    data.setUint32(40, samples * 2, Endian.little);
    var offset = 44;
    for (final block in blocks) {
      for (final sample in block) {
        data.setInt16(offset, sample, Endian.little);
        offset += 2;
      }
    }
    return out;
  }
}

final class ImaAdpcmEncoder {
  int _index = 0;

  Uint8List encode(Int16List pcm) {
    if (pcm.isEmpty) return Uint8List(0);
    final out = Uint8List(ImaAdpcm.headerBytes + pcm.length ~/ 2);
    var predictor = pcm.first;
    var index = _index;
    final header = ByteData.sublistView(out);
    header.setInt16(0, predictor, Endian.little);
    out[2] = index;

    var outputIndex = ImaAdpcm.headerBytes;
    var pending = 0;
    for (var i = 1; i < pcm.length; i++) {
      var diff = pcm[i] - predictor;
      var code = 0;
      if (diff < 0) {
        code = 8;
        diff = -diff;
      }
      var step = ImaAdpcm._steps[index];
      var delta = step >> 3;
      if (diff >= step) {
        code |= 4;
        diff -= step;
        delta += step;
      }
      step >>= 1;
      if (diff >= step) {
        code |= 2;
        diff -= step;
        delta += step;
      }
      step >>= 1;
      if (diff >= step) {
        code |= 1;
        delta += step;
      }
      predictor = (predictor + ((code & 8) != 0 ? -delta : delta)).clamp(
        -32768,
        32767,
      );
      index = (index + ImaAdpcm._indexes[code]).clamp(0, 88);
      if (i.isOdd) {
        pending = code;
      } else {
        out[outputIndex++] = pending | (code << 4);
      }
    }
    if ((pcm.length - 1).isOdd) out[outputIndex++] = pending;
    _index = index;
    return Uint8List.sublistView(out, 0, outputIndex);
  }
}
