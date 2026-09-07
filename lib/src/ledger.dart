import 'crypto/ed25519_service.dart' show fmtLocal;

/// Markdown 台账，与 tools/keygen.html 的 markdown() 输出同构（仅工具署名不同）。
String markdownLedger({
  required int activationStartSec,
  required int activationEndSec,
  required int expirySec,
  required List<String> tokens,
}) {
  final buf = StringBuffer()
    ..writeln('# 激活密钥台账（SKEY 密钥生成器 生成，请勿外传）')
    ..writeln()
    ..writeln(
      '- 激活窗口：${fmtLocal(activationStartSec)} → '
      '${fmtLocal(activationEndSec)}（仅此段可激活）',
    )
    ..writeln('- 授权截止：${fmtLocal(expirySec)}（到期 App 弹框并停录）')
    ..writeln()
    ..writeln('| # | 激活窗口 | 授权截止 | 密钥 |')
    ..writeln('| --: | --- | --- | --- |');
  for (var i = 0; i < tokens.length; i++) {
    buf.writeln(
      '| ${i + 1} | '
      '${fmtLocal(activationStartSec)} → ${fmtLocal(activationEndSec)} | '
      '${fmtLocal(expirySec)} | ${tokens[i]} |',
    );
  }
  return buf.toString();
}

/// 备份 txt 内容（与网页下载文件逐字同格式，便于跨工具回读）。
String backupText({
  required String privatePkcs8B64,
  required String publicHex,
}) {
  return 'SKEY 激活密钥 私钥备份（切勿外传）\n\n'
      '私钥 (PKCS8 base64):\n'
      '$privatePkcs8B64\n\n'
      '公钥 (hex, 粘贴进 lib/features/activation/activation_public.dart):\n'
      '$publicHex\n';
}

/// 从备份 txt / 任意粘贴文本里解析出私钥 b64（可带公钥行）。找不到返回 null。
({String private, String? public})? parseBackupText(String text) {
  // 优先按标注行抓取（兼容网页/本工具导出的备份，base64 可能被换行）。
  final privMatch = RegExp(
    r'私钥\s*\([^)]*PKCS8[^)]*\)\s*:\s*([A-Za-z0-9+/=\s]+?)(?=\n\s*\n|\n公钥|$)',
  ).firstMatch(text);
  if (privMatch != null) {
    final priv = privMatch.group(1)!.replaceAll(RegExp(r'\s+'), '');
    if (priv.isNotEmpty) {
      String? pub;
      final pubMatch = RegExp(r'公钥\s*\([^)]*\)\s*:\s*([0-9a-fA-F\s-]+)')
          .firstMatch(text);
      if (pubMatch != null) {
        pub = pubMatch.group(1)!.replaceAll(RegExp(r'[\s-]+'), '');
      }
      return (private: priv, public: pub);
    }
  }
  // 退路：整段去掉空白后若像 base64（无空格、纯 base64 字符）则视为私钥。
  final compact = text.replaceAll(RegExp(r'\s+'), '');
  if (RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(compact) &&
      compact.length >= 16 &&
      compact.length % 4 == 0) {
    return (private: compact, public: null);
  }
  return null;
}
