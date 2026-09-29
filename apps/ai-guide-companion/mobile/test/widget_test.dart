// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:guide_companion/main.dart';

void main() {
  testWidgets('shows the Passport connection flow', (tester) async {
    await tester.pumpWidget(const GuideCompanionApp());
    await tester.pump();

    expect(find.text('Passport Guide'), findsOneWidget);
    expect(find.text('Connect Passport'), findsOneWidget);
    expect(find.text('Scan and connect'), findsOneWidget);
    expect(find.text('Hold OK and speak'), findsOneWidget);
  });
}
