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

  Future<void> connect() async {
    await disconnect();
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
    await device.connect(license: License.nonprofit, mtu: 185);
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
    onState(GuideConnectionState.connected, 'Connected · MTU $mtu');
  }

  Future<void> send(int type, [List<int> payload = const []]) async {
    final rx = _rx;
    if (rx == null) throw StateError('Passport is not connected');
    final value = packet(type, payload);
    final maxPayload = (_device?.mtuNow ?? 23) - 3;
    if (value.length > maxPayload) {
      throw StateError('BLE packet exceeds negotiated MTU');
    }
    await rx.write(value, withoutResponse: false);
  }

  Future<void> sendText(int type, String text) async {
    final bytes = utf8.encode(text);
    final chunkSize = ((_device?.mtuNow ?? 23) - 4).clamp(1, 180);
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, bytes.length);
      await send(type, bytes.sublist(offset, end));
    }
  }

  Future<void> disconnect() async {
    await _notify?.cancel();
    await _connection?.cancel();
    await _scan?.cancel();
    _notify = null;
    _connection = null;
    _scan = null;
    _rx = null;
    final device = _device;
    _device = null;
    if (device != null && device.isConnected) await device.disconnect();
    onState(GuideConnectionState.disconnected, 'Not connected');
  }
}
