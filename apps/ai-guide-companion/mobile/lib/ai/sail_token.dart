import 'dart:convert';

import 'package:crypto/crypto.dart';

final class SailTokenSigner {
  const SailTokenSigner();

  String signature({
    required String accessKey,
    required String secretKey,
    required int timestamp,
    required int expiration,
  }) {
    final signKeyInfo = 'auth-v1/$accessKey/$timestamp/$expiration';
    final signKey = Hmac(
      sha256,
      utf8.encode(secretKey),
    ).convert(utf8.encode(signKeyInfo));
    return Hmac(
      sha256,
      utf8.encode(signKey.toString()),
    ).convert(const <int>[]).toString();
  }
}
