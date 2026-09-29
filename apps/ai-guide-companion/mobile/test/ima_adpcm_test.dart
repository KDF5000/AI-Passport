import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guide_companion/protocol/ima_adpcm.dart';

void main() {
  test('encodes a 20 ms 16 kHz block into one BLE-sized packet', () {
    final input = Int16List.fromList(
      List.generate(320, (i) {
        final period = i % 64;
        return ((period < 32 ? period : 63 - period) * 500 - 8000);
      }),
    );
    final encoded = ImaAdpcm.encode(input);
    expect(encoded.length, 164);
    final decoded = ImaAdpcm.decode(encoded);
    expect(decoded.length, 321);
    expect(decoded.first, input.first);
    final meanError =
        List.generate(
          input.length,
          (i) => (input[i] - decoded[i]).abs(),
        ).reduce((a, b) => a + b) ~/
        input.length;
    expect(meanError, lessThan(700));
  });

  test('writes a valid mono PCM wave header', () {
    final wav = ImaAdpcm.pcm16Wave([Int16List(320)], 16000);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(ByteData.sublistView(wav).getUint32(24, Endian.little), 16000);
  });
}
