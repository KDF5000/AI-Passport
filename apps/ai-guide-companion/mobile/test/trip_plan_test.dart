import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guide_companion/trip/trip_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test('uses the same full narration for guide text and speech', () {
    const generated = TripStop(
      name: '幻城剧场',
      time: '15:30',
      durationMinutes: 80,
      summary: '小屏摘要',
      guideScript: '这是实际播报的完整导游讲解。',
    );
    const legacy = TripStop(
      name: '入口',
      time: '10:00',
      durationMinutes: 20,
      summary: '旧路线只有摘要。',
    );

    expect(generated.guideNarration, '幻城剧场。这是实际播报的完整导游讲解。');
    expect(legacy.guideNarration, '入口。旧路线只有摘要。');
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

  test('migrates the single legacy trip into a trip library', () async {
    SharedPreferences.setMockInitialValues({
      'offlineTripPlanV1': jsonEncode(TripPlan.demo.toJson()),
    });

    final store = TripPlanStore();
    final library = await store.loadLibrary();

    expect(library.trips, hasLength(1));
    expect(library.selectedTrip.title, TripPlan.demo.title);
    final saved = (await SharedPreferences.getInstance()).getString(
      'offlineTripLibraryV2',
    );
    expect(saved, isNotNull);
  });

  test('round-trips multiple trips and the selected trip', () async {
    SharedPreferences.setMockInitialValues({});
    final second = TripPlan.demo.copyWith(title: '开封两日行程', destination: '开封');
    final store = TripPlanStore();

    await store.saveLibrary(
      TripLibrary(trips: [TripPlan.demo, second], selectedIndex: 1),
    );
    final restored = await store.loadLibrary();

    expect(restored.trips, hasLength(2));
    expect(restored.selectedIndex, 1);
    expect(restored.selectedTrip.title, '开封两日行程');
  });
}
