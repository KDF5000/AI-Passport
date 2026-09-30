// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guide_companion/main.dart';
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
  });
}
