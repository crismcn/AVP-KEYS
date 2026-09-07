import 'package:flutter_test/flutter_test.dart';
import 'package:splayer_keygen/src/ledger.dart';

String rep(String s, int n) => List.filled(n, s).join();

/// Markdown 台账 / 备份 txt 结构，与 tools/keygen.html 输出同构。
void main() {
  const rs = 1704038400;
  const re = rs + 600;
  const xa = re + 3600 * 8;
  final tokens = [rep('A', 170), rep('B', 170)];

  test('markdownLedger 头部与两行密钥', () {
    final md = markdownLedger(
        activationStartSec: rs, activationEndSec: re, expirySec: xa, tokens: tokens);
    expect(md, contains('激活密钥台账'));
    expect(md, contains('激活窗口'));
    expect(md, contains('授权截止'));
    expect(md, contains('| # | 激活窗口 | 授权截止 | 密钥 |'));
    expect(md, contains('| 1 |'));
    expect(md, contains('| 2 |'));
    expect(md, contains(tokens[0]));
    expect(md, contains(tokens[1]));
  });

  test('backupText 逐字含私钥/公钥标注，可被 parseBackupText 回读', () {
    final priv = 'MC4CAQAwBQYDK2VwBCIEIP${rep('x', 40)}';
    final pub = rep('ab', 32);
    final text = backupText(privatePkcs8B64: priv, publicHex: pub);
    expect(text, contains('私钥 (PKCS8 base64):'));
    expect(text, contains('$priv\n'));
    expect(text, contains('公钥 (hex'));
    final parsed = parseBackupText(text)!;
    expect(parsed.private, priv);
    expect(parsed.public, pub);
  });

  test('parseBackupText 兼容带换行的 base64', () {
    final priv = 'MC4CAQAwBQYDK2VwBCIEIPCAAAA==';
    // 模拟被软换行的 64 字符 base64
    final wrapped = 'MC4CAQAwBQYDK2VwBCIEIP\nCAAAA==';
    final text = '私钥 (PKCS8 base64):\n$wrapped\n\n公钥 (hex):\n${rep('0', 64)}\n';
    final parsed = parseBackupText(text)!;
    expect(parsed.private, priv);
  });

  test('parseBackupText 退路：纯 base64 一段视为私钥', () {
    final priv = 'MC4CAQAwBQYDK2VwBCIEIPCAAAA==';
    final parsed = parseBackupText(priv)!;
    expect(parsed.private, priv);
    expect(parsed.public, isNull);
    expect(parseBackupText('随便一段中文说明文字'), isNull);
  });
}
