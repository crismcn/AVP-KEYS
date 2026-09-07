import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:splayer_keygen/src/crypto/ed25519_service.dart';

/// signToken 输出、21B claims 布局、分组展示与网页一致的校验规则。
void main() {
  // 2024-01-01 00:00 UTC+8 = 1704038400 UTC 秒附近；用固定整数避免时区依赖。
  const rs = 1704038400; // 开始
  const re = rs + 600; // +10 分钟
  const xa = re + 3600 * 8; // +8 小时

  test('密钥串 = 170 大写 hex，末 64B 是 claims 的 Ed25519 签名', () async {
    final key = await EdKey.generate();
    final token = await signToken(
        key: key,
        activationStartSec: rs,
        activationEndSec: re,
        expirySec: xa,
        rng: Random(1));

    expect(token, matches(RegExp(r'^[0-9A-F]{170}$')), reason: '170 大写 hex');
    // 前 13 字节 claims 结构（随机数除外）：
    final raw = _hexToBytes(token);
    expect(raw.length, 85);
    expect(raw[0], 0x01, reason: '版本');
    expect(_readUint32(raw, 1), rs);
    expect(_readUint32(raw, 5), re);
    expect(_readUint32(raw, 9), xa);
    // 末 64B 签名验签通过：
    expect(
      await verifyPublic(
        message: raw.sublist(0, 21),
        signature: raw.sublist(21),
        publicKey: key.public,
      ),
      isTrue,
    );
    expect(await verifyTokenHex(token, key.public), isTrue);
    expect(token.startsWith('01000000'), isTrue, reason: '前两字节为版本+开始高位');
  });

  test('同窗口两次生成：前 13B 相同、随机数与密钥串不同', () async {
    final key = await EdKey.generate();
    final a = await signToken(
        key: key,
        activationStartSec: rs,
        activationEndSec: re,
        expirySec: xa,
        rng: Random(1));
    final b = await signToken(
        key: key,
        activationStartSec: rs,
        activationEndSec: re,
        expirySec: xa,
        rng: Random(2));
    expect(a.substring(0, 26), b.substring(0, 26),
        reason: '版本+三个时间 hex 相同');
    expect(a, isNot(b));
  });

  test("formatKey 每 4 位加 '-'，去掉后还原", () {
    const hex = 'ABCDEF0123456789';
    expect(formatKey(hex), 'ABCD-EF01-2345-6789');
    expect(formatKey('ABCD'), 'ABCD');
    expect(formatKey('ABCDEF01'), 'ABCD-EF01');
    final token = List.filled(85, 'AB').join();
    expect(formatKey(token).replaceAll('-', ''), token);
  });

  test('validateTimes 边界（文案与网页一致）', () {
    expect(validateTimes(
            activationStartSec: re,
            activationEndSec: re,
            expirySec: xa),
        '激活截止必须晚于激活开始');
    expect(validateTimes(
            activationStartSec: rs,
            activationEndSec: re,
            expirySec: re - 1),
        '授权截止不能早于激活截止');
    expect(validateTimes(
            activationStartSec: rs,
            activationEndSec: re,
            expirySec: uint32Max + 1),
        '时间超出 uint32，须早于 2106-02-07');
    expect(validateTimes(
            activationStartSec: rs,
            activationEndSec: re,
            expirySec: xa),
        isNull);
  });

  test('validateCount 边界', () {
    expect(validateCount(0), '数量须在 1–200 之间');
    expect(validateCount(201), '数量须在 1–200 之间');
    expect(validateCount(1), isNull);
    expect(validateCount(200), isNull);
  });
}

int _readUint32(List<int> b, int at) =>
    ((b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]) & 0xffffffff;

List<int> _hexToBytes(String hex) {
  final out = List<int>.filled(hex.length ~/ 2, 0);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
