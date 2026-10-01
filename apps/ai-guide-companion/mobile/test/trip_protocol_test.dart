import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guide_companion/protocol/guide_protocol.dart';
import 'package:guide_companion/protocol/trip_protocol.dart';
import 'package:guide_companion/trip/trip_plan.dart';

void main() {
  test('keeps playback request and cancellation packet IDs stable', () {
    expect(GuidePacketType.tripPlayRequest, 0x32);
    expect(GuidePacketType.tripPlayCancel, 0x33);
  });

  test('encodes route boundary and selected stop', () {
    final value = TripProtocol.begin(TripPlan.demo);

    expect(value, [GuidePacketType.tripBegin, TripPlan.demo.stops.length, 0]);
  });

  test('encodes a UTF-8 stop in one BLE packet', () {
    final stop = TripPlan.demo.stops[1].copyWith(completed: true);
    final value = TripProtocol.stop(1, stop);
    final timeLength = value[5];
    final nameLength = value[6];
    final timeStart = 7;
    final nameStart = timeStart + timeLength;
    final summaryStart = nameStart + nameLength;

    expect(value.first, GuidePacketType.tripStop);
    expect(value[1], 1);
    expect(value[2], 1);
    expect(value[3] | (value[4] << 8), stop.durationMinutes);
    expect(utf8.decode(value.sublist(timeStart, nameStart)), stop.time);
    expect(utf8.decode(value.sublist(nameStart, summaryStart)), stop.name);
    expect(utf8.decode(value.sublist(summaryStart)), stop.summary);
    expect(value.length, lessThanOrEqualTo(180));
  });
}
