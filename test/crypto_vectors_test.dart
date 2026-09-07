import 'package:cryptography/cryptography.dart' as cg;
import 'package:flutter_test/flutter_test.dart';
import 'package:splayer_keygen/src/crypto/ed25519_service.dart';

/// RFC 8032 标准测试向量：确认纯 Dart Ed25519（cryptography 包）与标准实现一致，
/// 因此与网页版 WebCrypto 签名在字节上互通。
void main() {
  final ed = cg.Ed25519();

  Future<void> checkVector({
    required List<int> seed,
    required String publicHex,
    required List<int> message,
    required String signatureHex,
  }) async {
    final keyPair = await ed.newKeyPairFromSeed(seed);
    final pub = await keyPair.extractPublicKey();
    expect(toHexLower(pub.bytes), publicHex, reason: '由 seed 推导的公钥');
    final sig = await ed.sign(message, keyPair: keyPair);
    expect(toHexLower(sig.bytes), signatureHex, reason: '签名应与 RFC 8032 一致');
  }

  test('RFC 8032 TEST 1（空消息）', () async {
    await checkVector(
      seed: [
        0x9d, 0x61, 0xb1, 0x9d, 0xef, 0xfd, 0x5a, 0x60, //
        0xba, 0x84, 0x4a, 0xf4, 0x92, 0xec, 0x2c, 0xc4,
        0x44, 0x49, 0xc5, 0x69, 0x7b, 0x32, 0x69, 0x19,
        0x70, 0x3b, 0xac, 0x03, 0x1c, 0xae, 0x7f, 0x60,
      ],
      publicHex: 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
      message: const <int>[],
      signatureHex: 'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
          '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b',
    );
  });

  test('RFC 8032 TEST 2（单字节消息 0x72）', () async {
    await checkVector(
      seed: [
        0x4c, 0xcd, 0x08, 0x9b, 0x28, 0xff, 0x96, 0xda, //
        0x9d, 0xb6, 0xc3, 0x46, 0xec, 0x11, 0x4e, 0x0f,
        0x5b, 0x8a, 0x31, 0x9f, 0x35, 0xab, 0xa6, 0x24,
        0xda, 0x8c, 0xf6, 0xed, 0x4f, 0xb8, 0xa6, 0xfb,
      ],
      publicHex: '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c',
      message: const [0x72],
      signatureHex: '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da'
          '085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00',
    );
  });
}
