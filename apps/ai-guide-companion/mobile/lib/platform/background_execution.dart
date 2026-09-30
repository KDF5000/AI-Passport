import 'package:flutter/services.dart';

abstract interface class BackgroundExecution {
  Future<bool> begin(String reason);

  Future<void> end();
}

final class IosBackgroundExecution implements BackgroundExecution {
  static const MethodChannel _channel = MethodChannel(
    'com.kdf5000.guideCompanion/background',
  );

  @override
  Future<bool> begin(String reason) async {
    final started = await _channel.invokeMethod<bool>('begin', {
      'reason': reason,
    });
    return started ?? false;
  }

  @override
  Future<void> end() => _channel.invokeMethod<void>('end');
}
