import 'dart:typed_data';

abstract final class GuidePacketType {
  static const recordingStart = 0x01;
  static const recordingAudio = 0x02;
  static const recordingEnd = 0x03;
  static const transcript = 0x10;
  static const answerText = 0x11;
  static const playbackStart = 0x12;
  static const playbackAudio = 0x13;
  static const responseEnd = 0x14;
  static const tripBegin = 0x20;
  static const tripTitle = 0x21;
  static const tripStop = 0x22;
  static const tripCommit = 0x23;
  static const tripSelect = 0x30;
  static const tripCompletion = 0x31;
  static const tripPlayRequest = 0x32;
  static const tripPlayCancel = 0x33;
  static const error = 0x7f;
}

abstract final class GuideBleIds {
  static const deviceName = 'Passport Guide';
  static const service = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const phoneWrites = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const passportNotifies = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
}

Uint8List packet(int type, [List<int> payload = const []]) =>
    Uint8List.fromList([type, ...payload]);

Uint8List sampleRatePacket(int type, int sampleRate) =>
    packet(type, [sampleRate & 0xff, (sampleRate >> 8) & 0xff]);
