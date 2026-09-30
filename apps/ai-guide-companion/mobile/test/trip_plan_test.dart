import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guide_companion/trip/trip_plan.dart';

void main() {
  test('round-trips a trip and its completion progress', () {
    final plan = TripPlan.demo.copyWith(
      currentIndex: 2,
      stops: [
        TripPlan.demo.stops.first.copyWith(completed: true),
        ...TripPlan.demo.stops.skip(1),
      ],
    );

    final restored = TripPlan.fromJson(
      (jsonDecode(jsonEncode(plan.toJson())) as Map).cast<String, Object?>(),
    );

    expect(restored.title, plan.title);
    expect(restored.currentIndex, 2);
    expect(restored.stops.length, plan.stops.length);
    expect(restored.stops.first.completed, isTrue);
    expect(restored.stops[2].name, '火车站剧场');
    expect(restored.destination, plan.destination);
    expect(restored.verificationItems, isNotEmpty);
  });

  test('copyWith preserves stop details when completion changes', () {
    final original = TripPlan.demo.stops.first;
    final completed = original.copyWith(completed: true);

    expect(completed.completed, isTrue);
    expect(completed.name, original.name);
    expect(completed.time, original.time);
    expect(completed.summary, original.summary);
  });

  test('loads a legacy saved trip without generated fields', () {
    final restored = TripPlan.fromJson({
      'title': '旧路线',
      'currentIndex': 0,
      'stops': [
        {
          'name': '旧站点',
          'time': '10:00',
          'durationMinutes': 30,
          'summary': '旧版摘要',
          'completed': true,
        },
      ],
    });

    expect(restored.destination, '旧路线');
    expect(restored.stops.single.guideScript, isEmpty);
    expect(restored.stops.single.completed, isTrue);
  });
}
