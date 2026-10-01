import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guide_companion/ai/ai_settings.dart';
import 'package:guide_companion/guide_controller.dart';
import 'package:guide_companion/main.dart';
import 'package:guide_companion/trip/trip_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('starts from an honest empty trip state', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const GuideCompanionApp());
    await tester.pumpAndSettle();

    expect(find.text('先把想去的地方\n变成一张行程票'), findsOneWidget);
    expect(find.text('创建新行程'), findsOneWidget);
    expect(find.text('开始'), findsOneWidget);
    expect(find.text('问导游'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('opens the AI trip builder', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const GuideCompanionApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('创建新行程'));
    await tester.pumpAndSettle();

    expect(find.text('新建行程'), findsOneWidget);
    expect(find.text('今天去哪里？'), findsOneWidget);
    expect(find.text('下一步 · 添加确定场次'), findsOneWidget);

    final destination = tester.widget<TextField>(
      find.widgetWithText(TextField, '目的地'),
    );
    expect(destination.controller?.text, isEmpty);

    final date = tester.widget<TextField>(
      find.widgetWithText(TextField, '游玩日期'),
    );
    final arrival = tester.widget<TextField>(
      find.widgetWithText(TextField, '到达'),
    );
    final departure = tester.widget<TextField>(
      find.widgetWithText(TextField, '离开'),
    );
    expect(date.readOnly, isTrue);
    expect(arrival.readOnly, isTrue);
    expect(departure.readOnly, isTrue);

    await tester.tap(find.widgetWithText(TextField, '游玩日期'));
    await tester.pumpAndSettle();
    expect(find.text('选择游玩日期'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextField, '到达'));
    await tester.pumpAndSettle();
    expect(find.text('选择到达时间'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('supports custom LLM and speech endpoints', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SettingsPage(initial: AiSettings())),
    );

    expect(find.text('LLM API'), findsOneWidget);
    expect(find.text('语音 API'), findsOneWidget);
    expect(find.text('模型 / Model'), findsOneWidget);
    expect(find.text('模型 / Endpoint ID'), findsNothing);
    expect(find.text('LLM API Endpoint'), findsOneWidget);
    final llmEndpoint = tester.widget<TextField>(
      find.widgetWithText(TextField, 'LLM API Endpoint'),
    );
    expect(llmEndpoint.controller?.text, AiSettings.defaultArkEndpoint);
    final llmEndpointTop = tester.getTopLeft(
      find.widgetWithText(TextField, 'LLM API Endpoint'),
    );
    final modelTop = tester.getTopLeft(
      find.widgetWithText(TextField, '模型 / Model'),
    );
    expect(llmEndpointTop.dy, lessThan(modelTop.dy));

    await tester.scrollUntilVisible(
      find.text('Speech SK'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Speech SK'), findsOneWidget);
    expect(find.text('Speech AppKey'), findsOneWidget);
    expect(find.text('Speech AK'), findsOneWidget);
    expect(find.text('ASR API Endpoint'), findsOneWidget);
    expect(find.text('TTS API Endpoint'), findsOneWidget);
    final asrEndpoint = tester.widget<TextField>(
      find.widgetWithText(TextField, 'ASR API Endpoint'),
    );
    final ttsEndpoint = tester.widget<TextField>(
      find.widgetWithText(TextField, 'TTS API Endpoint'),
    );
    expect(asrEndpoint.controller?.text, AiSettings.defaultAsrEndpoint);
    expect(ttsEndpoint.controller?.text, AiSettings.defaultTtsEndpoint);
    final asrTop = tester.getTopLeft(
      find.widgetWithText(TextField, 'ASR API Endpoint'),
    );
    final appKeyTop = tester.getTopLeft(
      find.widgetWithText(TextField, 'Speech AppKey'),
    );
    expect(asrTop.dy, lessThan(appKeyTop.dy));
  });

  testWidgets('shows a high-contrast Bluetooth icon while disconnected', (
    tester,
  ) async {
    final controller = GuideController();
    controller.trip = const TripPlan(
      title: '测试行程',
      destination: '测试地点',
      date: '2026-10-04',
      stops: [
        TripStop(
          name: '第一站',
          time: '10:00',
          durationMinutes: 40,
          summary: '测试讲解',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TripTicketView(controller: controller, onOpenLibrary: () {}),
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.bluetooth));
    expect(icon.color, Colors.white);
    expect(find.text('连接'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('shows saved trips and a persistent create action', (
    tester,
  ) async {
    final controller = GuideController();
    controller
      ..trips = [
        TripPlan.demo,
        TripPlan.demo.copyWith(
          title: '开封两日行程',
          destination: '开封',
          date: '2026-10-05',
        ),
      ]
      ..trip = TripPlan.demo
      ..selectedTripIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: TripLibraryPage(
          controller: controller,
          onCreateTrip: () async {},
        ),
      ),
    );

    expect(find.text('我的行程'), findsOneWidget);
    expect(find.text('只有河南 · 一日路线'), findsOneWidget);
    expect(find.text('开封两日行程'), findsOneWidget);
    expect(find.text('新建行程'), findsOneWidget);
    controller.dispose();
  });
}
