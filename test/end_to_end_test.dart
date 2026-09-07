import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:splayer_keygen/src/crypto/ed25519_service.dart';
import 'package:splayer_keygen/src/ledger.dart';

/// 一次完整签发：密钥对 → 批量签名 → 台账 → 备份 txt → 下次启动用备份恢复验签。
void main() {
  test('端到端：签发一批密钥并全部可用备份恢复的私钥验证', () async {
    final key = await EdKey.generate();
    const rs = 1704038400;
    const re = rs + 3600 * 24 * 7; // +7 天
    const xa = re + 3600 * 24 * 365; // 激活截止后 +365 天

    // 1) 签发 3 条
    final tokens = <String>[];
    for (var i = 0; i < 3; i++) {
      tokens.add(await signToken(
        key: key,
        activationStartSec: rs,
        activationEndSec: re,
        expirySec: xa,
        rng: Random(100 + i),
      ));
    }
    expect(tokens.toSet().length, 3, reason: '三条各不相同');

    // 2) 台账可复制
    final md = markdownLedger(
        activationStartSec: rs, activationEndSec: re, expirySec: xa, tokens: tokens);
    for (final t in tokens) {
      expect(md, contains(t));
    }

    // 3) 备份 txt 落盘内容，模拟“换一台机器”仅靠 txt 恢复
    final backup = backupText(privatePkcs8B64: key.pkcs8B64, publicHex: key.publicHex);
    final parsed = parseBackupText(backup)!;
    final restored = await EdKey.fromPkcs8B64(parsed.private);
    expect(restored.publicHex, key.publicHex, reason: '仅私钥即可恢复公钥');
    expect(restored.publicHexMatches(parsed.public!), isTrue,
        reason: '备份里的公钥行与私钥匹配');

    // 4) 恢复出的私钥能验证最初签发的每条密钥
    for (final t in tokens) {
      expect(await verifyTokenHex(t, restored.public), isTrue);
    }
  });

  test('私钥与公钥不匹配时 publicHexMatches=false', () async {
    final a = await EdKey.generate();
    final b = await EdKey.generate();
    expect(a.publicHexMatches(b.publicHex), isFalse);
  });
}
