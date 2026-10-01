import 'package:flutter_test/flutter_test.dart';
import 'package:guide_companion/protocol/passport_operation.dart';

void main() {
  test('Passport can cancel an active offline playback', () {
    final state = PassportOperationState()
      ..start(7, PassportOperationKind.offlinePlayback);

    expect(state.cancel(7), PassportOperationKind.offlinePlayback);
    expect(state.operation, isNull);
    expect(state.kind, isNull);
  });

  test('Passport can cancel an active AI conversation', () {
    final state = PassportOperationState()
      ..start(8, PassportOperationKind.conversation);

    expect(state.cancel(8), PassportOperationKind.conversation);
    expect(state.operation, isNull);
    expect(state.kind, isNull);
  });

  test('stale cancellation cannot cancel a newer operation', () {
    final state = PassportOperationState()
      ..start(9, PassportOperationKind.conversation);

    expect(state.cancel(8), isNull);
    expect(state.operation, 9);
    expect(state.kind, PassportOperationKind.conversation);
  });
}
