import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

final class VolcSpeechFrame {
  const VolcSpeechFrame({
    required this.messageType,
    required this.serialization,
    required this.compression,
    required this.payload,
    this.flags = 0,
    this.sequence,
    this.errorCode,
  });

  final int messageType;
  final int flags;
  final int serialization;
  final int compression;
  final int? sequence;
  final int? errorCode;
  final Uint8List payload;

  bool get isLast => flags & VolcSpeechProtocol.negativeSequence != 0;
}

abstract final class VolcSpeechProtocol {
  static const clientFullRequest = 1;
  static const clientAudioOnly = 2;
  static const serverFullResponse = 9;
  static const serverAudioOnly = 10;
  static const serverError = 15;

  static const noSequence = 0;
  static const positiveSequence = 1;
  static const negativeSequence = 2;
  static const negativeWithSequence = 3;

  static const json = 1;
  static const raw = 0;
  static const gzip = 1;
  static const noCompression = 0;

  static Uint8List frame(VolcSpeechFrame value) {
    final payload = switch (value.compression) {
      gzip => Uint8List.fromList(GZipCodec().encode(value.payload)),
      noCompression => value.payload,
      _ => throw const FormatException('Unsupported speech compression'),
    };
    final out = BytesBuilder(copy: false);
    out.add([
      0x11,
      ((value.messageType & 0x0f) << 4) | (value.flags & 0x0f),
      ((value.serialization & 0x0f) << 4) | (value.compression & 0x0f),
      0x00,
    ]);
    if (value.flags & positiveSequence != 0) {
      if (value.sequence == null) {
        throw const FormatException('Speech sequence is required by flags');
      }
      final sequence = ByteData(4)..setInt32(0, value.sequence!);
      out.add(sequence.buffer.asUint8List());
    }
    final size = ByteData(4)..setUint32(0, payload.length);
    out
      ..add(size.buffer.asUint8List())
      ..add(payload);
    return out.takeBytes();
  }

  static VolcSpeechFrame parse(Uint8List bytes) {
    if (bytes.length < 8) {
      throw const FormatException('Short Volcengine speech frame');
    }
    final headerSize = (bytes[0] & 0x0f) * 4;
    if (headerSize < 4 || bytes.length < headerSize + 4) {
      throw const FormatException('Unsupported Volcengine speech header size');
    }
    final messageType = bytes[1] >> 4;
    final flags = bytes[1] & 0x0f;
    final serialization = bytes[2] >> 4;
    final compression = bytes[2] & 0x0f;
    final data = ByteData.sublistView(bytes);
    var offset = headerSize;
    int? sequence;
    if (flags & positiveSequence != 0) {
      if (bytes.length < offset + 4) {
        throw const FormatException('Truncated speech sequence');
      }
      sequence = data.getInt32(offset);
      offset += 4;
    }
    if (flags & 0x04 != 0) {
      if (bytes.length < offset + 4) {
        throw const FormatException('Truncated speech event');
      }
      offset += 4;
    }

    int? errorCode;
    if (messageType == serverError) {
      if (bytes.length < offset + 8) {
        throw const FormatException('Truncated speech error');
      }
      errorCode = data.getInt32(offset);
      offset += 4;
    }
    if (bytes.length < offset + 4) {
      throw const FormatException('Truncated speech payload size');
    }
    final payloadSize = data.getUint32(offset);
    offset += 4;
    if (bytes.length < offset + payloadSize) {
      throw const FormatException('Truncated Volcengine speech payload');
    }
    final encoded = Uint8List.sublistView(bytes, offset, offset + payloadSize);
    final payload = switch (compression) {
      gzip => Uint8List.fromList(GZipCodec().decode(encoded)),
      noCompression => encoded,
      _ => throw const FormatException('Unsupported speech compression'),
    };
    return VolcSpeechFrame(
      messageType: messageType,
      flags: flags,
      serialization: serialization,
      compression: compression,
      sequence: sequence,
      errorCode: errorCode,
      payload: payload,
    );
  }

  static Map<String, Object?> decodeJsonPayload(Uint8List payload) {
    final decoded = jsonDecode(utf8.decode(payload));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Volcengine JSON payload is not an object');
    }
    return decoded;
  }
}
