import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guide_companion/platform/background_execution.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.kdf5000.guideCompanion/background');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('begins and ends one iOS background task', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'begin';
        });

    final execution = IosBackgroundExecution();
    expect(await execution.begin('Passport voice question'), isTrue);
    await execution.end();

    expect(calls, hasLength(2));
    expect(calls[0].method, 'begin');
    expect(calls[0].arguments, {'reason': 'Passport voice question'});
    expect(calls[1].method, 'end');
  });
}
