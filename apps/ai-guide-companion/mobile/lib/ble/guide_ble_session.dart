import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../protocol/guide_protocol.dart';

enum GuideConnectionState { disconnected, scanning, connecting, connected }

final class GuideBleSession {
  GuideBleSession({required this.onPacket, required this.onState});

  final void Function(Uint8List packet) onPacket;
  final void Function(GuideConnectionState state, String detail) onState;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _rx;
  StreamSubscription<List<ScanResult>>? _scan;
  StreamSubscription<List<int>>? _notify;
  StreamSubscription<BluetoothConnectionState>? _connection;
  Future<void> _writeTail = Future.value();
  Future<void>? _initializing;

  Future<void> initialize() =>
      _initializing ??= FlutterBluePlus.setOptions(restoreState: true);

  Future<bool> restoreConnection() async {
    await initialize();
    if (_rx != null && _device?.isConnected == true) return true;
    await _waitForAdapter();
    onState(GuideConnectionState.connecting, 'Restoring Passport connection');
    final device = await _findSystemDevice(
      attempts: 8,
      interval: const Duration(milliseconds: 250),
    );
    if (device == null) {
      onState(GuideConnectionState.disconnected, 'Passport not connected');
      return false;
    }
    try {
      await _clearConnection(disconnectDevice: false);
      await _attach(device, connectFirst: !device.isConnected, restored: true);
      return true;
    } catch (_) {
      await _clearConnection(disconnectDevice: false);
      rethrow;
    }
  }

  Future<void> connect() async {
    await initialize();
    await _waitForAdapter();
    if (_rx != null && _device?.isConnected == true) {
      onState(
        GuideConnectionState.connected,
        'Connected · MTU ${_device!.mtuNow}',
      );
      return;
    }

    onState(GuideConnectionState.connecting, 'Checking existing connection');
    final existing = await _findSystemDevice(
      attempts: 3,
      interval: const Duration(milliseconds: 200),
    );
    if (existing != null) {
      await _clearConnection(disconnectDevice: false);
      await _attach(
        existing,
        connectFirst: !existing.isConnected,
        restored: true,
      );
      return;
    }

    await _clearConnection(disconnectDevice: true);
    onState(GuideConnectionState.scanning, 'Looking for Passport Guide');
    final found = Completer<BluetoothDevice>();
    _scan = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        if (result.advertisementData.advName == GuideBleIds.deviceName ||
            result.advertisementData.serviceUuids.contains(
              Guid(GuideBleIds.service),
            )) {
          if (!found.isCompleted) found.complete(result.device);
          break;
        }
      }
    });
    await FlutterBluePlus.startScan(
      withServices: [Guid(GuideBleIds.service)],
      timeout: const Duration(seconds: 12),
    );
    BluetoothDevice device;
    try {
      device = await found.future.timeout(const Duration(seconds: 13));
    } finally {
      await FlutterBluePlus.stopScan();
      await _scan?.cancel();
      _scan = null;
    }

    onState(GuideConnectionState.connecting, 'Connecting');
    await _attach(device, connectFirst: true);
  }

  Future<void> _waitForAdapter() async {
    if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on) return;
    await FlutterBluePlus.adapterState
        .where((state) => state == BluetoothAdapterState.on)
        .first
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw StateError('Bluetooth is not ready'),
        );
  }

  Future<BluetoothDevice?> _findSystemDevice({
    required int attempts,
    required Duration interval,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt += 1) {
      final devices = await FlutterBluePlus.systemDevices([
        Guid(GuideBleIds.service),
      ]);
      if (devices.isNotEmpty) return devices.first;

      if (attempt + 1 < attempts) await Future<void>.delayed(interval);
    }
    return null;
  }

  Future<void> _attach(
    BluetoothDevice device, {
    required bool connectFirst,
    bool restored = false,
  }) async {
    if (connectFirst) {
      await device.connect(license: License.nonprofit, mtu: 185);
    }
    _device = device;
    _connection = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _rx = null;
        onState(GuideConnectionState.disconnected, 'Passport disconnected');
      }
    });
    final services = await device.discoverServices();
    final service = services
        .where((item) => item.serviceUuid == Guid(GuideBleIds.service))
        .firstOrNull;
    if (service == null) throw StateError('Guide BLE service not found');
    final rx = service.characteristics
        .where(
          (item) => item.characteristicUuid == Guid(GuideBleIds.phoneWrites),
        )
        .firstOrNull;
    final tx = service.characteristics
        .where(
          (item) =>
              item.characteristicUuid == Guid(GuideBleIds.passportNotifies),
        )
        .firstOrNull;
    if (rx == null || tx == null) {
      throw StateError('Guide BLE characteristics not found');
    }
    _rx = rx;
    _notify = tx.lastValueStream.listen((value) {
      if (value.isNotEmpty) onPacket(Uint8List.fromList(value));
    });
    await tx.setNotifyValue(true);
    final mtu = device.mtuNow;
    if (mtu < 168) {
      throw StateError('BLE MTU $mtu is too small; reconnect and retry');
    }
    onState(
      GuideConnectionState.connected,
      '${restored ? "Restored" : "Connected"} · MTU $mtu',
    );
  }

  Future<void> send(int type, [List<int> payload = const []]) async {
    return _send(type, payload, withoutResponse: false);
  }

  Future<void> sendAudio(List<int> payload) async {
    return _send(GuidePacketType.playbackAudio, payload, withoutResponse: true);
  }

  Future<void> _send(
    int type,
    List<int> payload, {
    required bool withoutResponse,
  }) async {
    final value = packet(type, payload);
    final result = Completer<void>();
    _writeTail = _writeTail.then((_) async {
      try {
        final rx = _rx;
        if (rx == null) throw StateError('Passport is not connected');
        if (withoutResponse && !rx.properties.writeWithoutResponse) {
          throw StateError('Passport does not support streaming BLE writes');
        }
        final maxPayload = (_device?.mtuNow ?? 23) - 3;
        if (value.length > maxPayload) {
          throw StateError('BLE packet exceeds negotiated MTU');
        }
        await rx.write(value, withoutResponse: withoutResponse);
        result.complete();
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<void> sendText(int type, String text) async {
    final chunkSize = ((_device?.mtuNow ?? 23) - 4).clamp(1, 180);
    var chunk = <int>[];
    for (final rune in text.runes) {
      final encoded = utf8.encode(String.fromCharCode(rune));
      if (chunk.isNotEmpty && chunk.length + encoded.length > chunkSize) {
        await send(type, chunk);
        chunk = <int>[];
      }
      chunk.addAll(encoded);
    }
    if (chunk.isNotEmpty) await send(type, chunk);
  }

  Future<void> disconnect() async {
    await _clearConnection(disconnectDevice: true);
    onState(GuideConnectionState.disconnected, 'Not connected');
  }

  Future<void> _clearConnection({required bool disconnectDevice}) async {
    await _notify?.cancel();
    await _connection?.cancel();
    await _scan?.cancel();
    _notify = null;
    _connection = null;
    _scan = null;
    _rx = null;
    final device = _device;
    _device = null;
    if (disconnectDevice && device != null && device.isConnected) {
      await device.disconnect();
    }
  }
}
