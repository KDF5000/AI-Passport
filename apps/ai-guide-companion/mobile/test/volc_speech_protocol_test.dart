import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guide_companion/ai/volc_speech_protocol.dart';

void main() {
  test('round-trips a JSON Volcengine speech frame', () {
    final frame = VolcSpeechFrame(
      messageType: VolcSpeechProtocol.clientFullRequest,
      serialization: VolcSpeechProtocol.json,
      compression: VolcSpeechProtocol.noCompression,
      payload: Uint8List(0),
    );

    final encoded = VolcSpeechProtocol.frame(
      VolcSpeechFrame(
        messageType: frame.messageType,
        serialization: frame.serialization,
        compression: frame.compression,
        payload: Uint8List.fromList(utf8.encode('{"ok":true}')),
      ),
    );
    final decoded = VolcSpeechProtocol.parse(encoded);

    expect(decoded.messageType, frame.messageType);
    expect(decoded.serialization, frame.serialization);
    expect(decoded.compression, frame.compression);
    expect(utf8.decode(decoded.payload), '{"ok":true}');
  });

  test('round-trips gzip payload, sequence, and final flag', () {
    final payload = Uint8List.fromList(
      List<int>.generate(3200, (i) => i & 0xff),
    );
    final encoded = VolcSpeechProtocol.frame(
      VolcSpeechFrame(
        messageType: VolcSpeechProtocol.clientAudioOnly,
        flags: VolcSpeechProtocol.negativeWithSequence,
        sequence: -7,
        serialization: VolcSpeechProtocol.raw,
        compression: VolcSpeechProtocol.gzip,
        payload: payload,
      ),
    );
    final decoded = VolcSpeechProtocol.parse(encoded);

    expect(encoded[0], 0x11);
    expect(encoded[1], 0x23);
    expect(decoded.sequence, -7);
    expect(decoded.isLast, isTrue);
    expect(decoded.payload, payload);
  });
}
