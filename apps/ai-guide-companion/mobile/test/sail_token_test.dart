import 'package:flutter_test/flutter_test.dart';
import 'package:guide_companion/ai/sail_token.dart';

void main() {
  test('creates a deterministic HMAC token signature', () {
    const signer = SailTokenSigner();

    final first = signer.signature(
      accessKey: 'ak-test',
      secretKey: 'sk-test',
      timestamp: 1780000000,
      expiration: 86400,
    );
    final second = signer.signature(
      accessKey: 'ak-test',
      secretKey: 'sk-test',
      timestamp: 1780000000,
      expiration: 86400,
    );

    expect(first, second);
    expect(first, hasLength(64));
  });
}
