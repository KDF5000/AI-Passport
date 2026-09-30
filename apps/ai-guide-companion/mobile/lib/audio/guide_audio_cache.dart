import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

final class GuideAudioCache {
  Future<File> _file(String key) async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/offline_guides');
    await directory.create(recursive: true);
    final digest = sha256.convert(key.codeUnits);
    return File('${directory.path}/$digest.wav');
  }

  Future<bool> contains(String key) async => await (await _file(key)).exists();

  Future<Uint8List?> read(String key) async {
    final file = await _file(key);
    return await file.exists() ? file.readAsBytes() : null;
  }

  Future<void> write(String key, Uint8List bytes) async {
    final file = await _file(key);
    await file.writeAsBytes(bytes, flush: true);
  }
}
