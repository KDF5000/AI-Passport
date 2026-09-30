import 'dart:convert';
import 'dart:typed_data';

import '../trip/trip_plan.dart';
import 'guide_protocol.dart';

abstract final class TripProtocol {
  static Uint8List begin(TripPlan plan) => Uint8List.fromList([
    GuidePacketType.tripBegin,
    plan.stops.length,
    plan.currentIndex,
  ]);

  static Uint8List stop(int index, TripStop stop) {
    final time = utf8.encode(stop.time);
    final name = utf8.encode(stop.name);
    final summary = utf8.encode(stop.summary);
    if (time.length > 255 || name.length > 255) {
      throw const FormatException('Trip stop field is too long');
    }
    final packet = BytesBuilder(copy: false)
      ..add([
        GuidePacketType.tripStop,
        index,
        stop.completed ? 1 : 0,
        stop.durationMinutes & 0xff,
        (stop.durationMinutes >> 8) & 0xff,
        time.length,
        name.length,
      ])
      ..add(time)
      ..add(name)
      ..add(summary);
    final value = packet.takeBytes();
    if (value.length > 180) {
      throw const FormatException('Trip stop exceeds one BLE packet');
    }
    return value;
  }
}
