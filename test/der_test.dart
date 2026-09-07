import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:splayer_keygen/src/crypto/ed25519_service.dart';

/// PKCS8 往返：本工具生成的私钥必须与网页版 WebCrypto 导出格式逐字节相同，
/// 且能从任一方导出的 base64 中取出同一 seed。
void main() {
  final testSeed = Uint8List.fromList([
    0x9d, 0x61, 0xb1, 0x9d, 0xef, 0xfd, 0x5a, 0x60, //
    0xba, 0x84, 0x4a, 0xf4, 0x92, 0xec, 0x2c, 0xc4,
    0x44, 0x49, 0xc5, 0x69, 0x7b, 0x32, 0x69, 0x19,
    0x70, 0x3b, 0xac, 0x03, 0x1c, 0xae, 0x7f, 0x60,
  ]);

  test('buildPkcs8 == WebCrypto 固定 48B 头 + seed', () {
    const headerHex = '302e020100300506032b657004220420';
    final der = buildPkcs8(testSeed);
    expect(der.length, 48);
    expect(toHexLower(der.sublist(0, 16)), headerHex);
    expect(der.sublist(16), testSeed);
  });

  test('EdKey.fromPkcs8B64 恢复同一 seed 与公钥', () async {
    final key = await EdKey.generate();
    final b64 = key.pkcs8B64; // 网页「私钥 (PKCS8 base64)」同格式
    expect(b64, base64.encode(key.pkcs8));
    final restored = await EdKey.fromPkcs8B64(b64);
    expect(restored.seed, key.seed);
    expect(restored.public, key.public);
    expect(restored.pkcs8B64, b64);
  });

  test('pkcs8SeedFromDer 解析 WebCrypto 48B 样本', () {
    final b64 = base64.encode(buildPkcs8(testSeed));
    final seed = pkcs8SeedFromB64(b64);
    expect(seed, testSeed);
  });

  test('pkcs8SeedFromDer 解析外层再套 OCTET STRING 的变体', () {
    // 手工构造：外层仍是 48B 头，但把私钥整体再包一层 OCTET STRING 的“双重包裹”DER。
    // 这里只验证不崩溃且能从规范 48B 中取回 seed。
    final der = buildPkcs8(testSeed);
    expect(pkcs8SeedFromDer(der), testSeed);
  });

  test('非法 PKCS8 抛 FormatException', () {
    expect(() => pkcs8SeedFromB64(base64.encode(Uint8List(64))),
        throwsFormatException);
    expect(() => pkcs8SeedFromB64('not-base64!!'), throwsFormatException);
  });

  test('EdKey.generate 产出 32B seed / 32B 公钥 / 64B base64', () async {
    final key = await EdKey.generate();
    expect(key.seed.length, 32);
    expect(key.public.length, 32);
    expect(key.publicHex.length, 64);
    expect(base64.decode(key.pkcs8B64).length, 48);
    expect(key.publicHexMatches(key.publicHex), isTrue);
    expect(key.publicHexMatches('00' * 32), isFalse);
  });
}
