import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as cg;

/// AVP KEYS 激活密钥的 Ed25519 服务。
///
/// 输出格式与 tools/keygen.html（WebCrypto 版）**字节级一致**，便于跨工具续用：
/// 私钥 = PKCS8 DER base64、公钥 = 32B 小写 hex、密钥串 = 「21B claims ‖ 64B 签名」
/// 的大写 hex（170 字符，无分隔符）。claims 布局见 [signToken] 注释。
///
/// 与网页版的关键差别：WebCrypto 无法从私钥反推公钥，这里从 32B seed 直接推导，
/// 所以只粘贴私钥也能恢复配套公钥。

final cg.Ed25519 _ed = cg.Ed25519();

const int uint32Max = 0xFFFFFFFF; // 末个可表示纪元秒：2106-02-07
const int _claimsVersion = 0x01;
const int _claimsLen = 21;
const int _sigLen = 64;
const int _tokenLen = _claimsLen + _sigLen; // 85 B

/// Ed25519 私钥=32B seed；PKCS8 用 RFC 8410 固定头（WebCrypto 同款，48B）。
final Uint8List _pkcs8Header = Uint8List.fromList(const [
  0x30, 0x2e, // SEQUENCE
  0x02, 0x01, 0x00, // INTEGER version 0
  0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, // SEQUENCE{ OID 1.3.101.112 }
  0x04, 0x22, 0x04, 0x20, // OCTET STRING{ OCTET STRING(32) }
]);

/// 一串可签名/验签的 Ed25519 密钥对。seed 即 RFC 8032 的 32B 私钥。
class EdKey {
  final Uint8List seed;
  final Uint8List public;
  final cg.KeyPair _pair;

  EdKey._(this.seed, this.public, this._pair);

  static Future<EdKey> _fromSeedBytes(Uint8List seed) async {
    if (seed.length != 32) {
      throw ArgumentError('私钥 seed 须为 32 字节，实际 ${seed.length}');
    }
    final pair = await _ed.newKeyPairFromSeed(seed);
    final pub = await pair.extractPublicKey();
    return EdKey._(seed, Uint8List.fromList(pub.bytes), pair);
  }

  /// 由 PKCS8 DER base64（网页「下载私钥备份」那行，或本工具导出）恢复密钥对。
  static Future<EdKey> fromPkcs8B64(String b64) async {
    final seed = pkcs8SeedFromB64(b64);
    return _fromSeedBytes(seed);
  }

  /// 生成一个全新密钥对（随机 32B seed）。
  static Future<EdKey> generate() async {
    final rng = Random.secure();
    final seed = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      seed[i] = rng.nextInt(256);
    }
    return _fromSeedBytes(seed);
  }

  /// PKCS8 DER 原始字节（48B）。
  Uint8List get pkcs8 => buildPkcs8(seed);

  /// 与网页「私钥 (PKCS8 base64)」同格式。
  String get pkcs8B64 => base64.encode(pkcs8);

  /// 与网页「公钥 (hex)」同格式（小写 64 字符）。
  String get publicHex => toHexLower(public);

  /// 用本私钥签名 message，返回 64B 签名。
  Future<Uint8List> sign(List<int> message) async {
    final sig = await _ed.sign(message, keyPair: _pair);
    return Uint8List.fromList(sig.bytes);
  }

  /// 公钥 hex（32B）与本私钥是否匹配。
  /// seed 可直接推导出唯一公钥，所以这里做字节级比对（比网页的签名探针更强）。
  Future<bool> publicHexMatches(String publicHex) async {
    final pubBytes = _fromHexOrNull(publicHex);
    if (pubBytes == null || pubBytes.length != 32) return false;
    return _sameBytes(pubBytes, public);
  }
}

// ---------------------------------------------------------------------------
// PKCS8（RFC 8410，Ed25519）解析/构建
// ---------------------------------------------------------------------------

/// 由 seed 组装 48B PKCS8 DER（与 WebCrypto 导出逐字节一致）。
Uint8List buildPkcs8(List<int> seed) {
  if (seed.length != 32) throw ArgumentError('seed 须为 32 字节');
  final out = Uint8List(_pkcs8Header.length + 32);
  out.setRange(0, _pkcs8Header.length, _pkcs8Header);
  out.setRange(_pkcs8Header.length, out.length, seed);
  return out;
}

/// 从 PKCS8 DER base64 中取出 32B seed。
/// 网页 WebCrypto 导出的是 48B 固定头版本；为兼容 openssl 等带公钥/属性的变体，
/// 这里按 DER 结构定位 OID(1.3.101.112) 之后的首个内层 32B OCTET STRING。
Uint8List pkcs8SeedFromB64(String b64) {
  final der = b64decode(b64);
  final seed = pkcs8SeedFromDer(der);
  if (seed == null) {
    throw FormatException('不是有效的 Ed25519 PKCS8 私钥');
  }
  return seed;
}

Uint8List? pkcs8SeedFromDer(Uint8List der) {
  // 快速路径：48B WebCrypto 固定头。
  if (der.length == 48) {
    var ok = true;
    for (var i = 0; i < _pkcs8Header.length; i++) {
      if (der[i] != _pkcs8Header[i]) {
        ok = false;
        break;
      }
    }
    // 固定头仅占 16 字节（302e…0420），种子是其后到文件尾的 32 字节。
    if (ok) return der.sublist(_pkcs8Header.length);
  }
  try {
    final top = _derChildren(der, 0);
    if (top.isEmpty || top.first.tag != 0x30) return null;
    // 外层 SEQUENCE 的子节点里找：算法 SEQ 含 OID(1.3.101.112)，其后首个 OCTET STRING 载 seed。
    final oidBytes = Uint8List.fromList(const [0x2b, 0x65, 0x70]);
    var seenAlgOid = false;
    for (final node in _derChildren(top.first.value, 0)) {
      if (node.tag == 0x30) {
        if (_contains(node.value, oidBytes)) seenAlgOid = true;
        continue;
      }
      if (seenAlgOid && node.tag == 0x04) {
        final seed = _unwrapSeedOctet(node.value);
        if (seed != null) return seed;
      }
    }
  } catch (_) {
    return null;
  }
  return null;
}

/// OCTET STRING 内层可能是裸 32B（RFC 8410 允许两种编码）或再套一层 OCTET STRING。
Uint8List? _unwrapSeedOctet(Uint8List value) {
  if (value.length == 32) return value;
  if (value.length > 2 && value[0] == 0x04) {
    try {
      final inner = _derChildren(value, 0);
      if (inner.isNotEmpty &&
          inner.first.tag == 0x04 &&
          inner.first.value.length == 32) {
        return inner.first.value;
      }
    } catch (_) {}
  }
  return null;
}

// 最小 DER TLV 阅读器（只处理 DER 短/长长度形式）。
class _DerNode {
  final int tag;
  final Uint8List value;
  const _DerNode(this.tag, this.value);
}

List<_DerNode> _derChildren(Uint8List b, int start) {
  final nodes = <_DerNode>[];
  var off = start;
  while (off < b.length) {
    final tag = b[off];
    var i = off + 1;
    var len = b[i];
    i += 1;
    if (len == 0x80) throw const FormatException('不支持的 BER 长度形式');
    if (len > 0x7f) {
      final n = len & 0x7f;
      len = 0;
      for (var k = 0; k < n; k++) {
        len = (len << 8) | b[i + k];
      }
      i += n;
    }
    final value = Uint8List.sublistView(b, i, i + len);
    nodes.add(_DerNode(tag, value));
    off = i + len;
  }
  return nodes;
}

bool _contains(Uint8List haystack, Uint8List needle) {
  if (needle.length > haystack.length) return false;
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// 编码工具
// ---------------------------------------------------------------------------

String b64encode(List<int> bytes) => base64.encode(bytes);

Uint8List b64decode(String s) =>
    base64.decode(s.replaceAll(RegExp(r'\s+'), ''));

String toHexLower(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

String toHexUpper(List<int> bytes) => toHexLower(bytes).toUpperCase();

Uint8List? _fromHexOrNull(String s) {
  final t = s.replaceAll(RegExp(r'\s+'), '').replaceAll('-', '');
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(t) || t.length.isOdd) return null;
  final out = Uint8List(t.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(t.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// 网页 formatKey：每 4 位 '-' 分组展示（复制时用原始无分隔串）。
String formatKey(String tokenHex) {
  final buf = StringBuffer();
  for (var i = 0; i < tokenHex.length; i += 4) {
    if (i > 0) buf.write('-');
    final end = (i + 4 < tokenHex.length) ? i + 4 : tokenHex.length;
    buf.write(tokenHex.substring(i, end));
  }
  return buf.toString();
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// 通用验签
// ---------------------------------------------------------------------------

/// 用 32B 原始公钥验签（message 原样、signature 64B）。
Future<bool> verifyPublic({
  required List<int> message,
  required List<int> signature,
  required List<int> publicKey,
}) async {
  final pub = cg.SimplePublicKey(
    Uint8List.fromList(publicKey),
    type: cg.KeyPairType.ed25519,
  );
  final sig = cg.Signature(Uint8List.fromList(signature), publicKey: pub);
  // cryptography 的 verify 仅收 signature；公钥已内嵌在 Signature 里。
  return _ed.verify(message, signature: sig);
}

/// 验签整个密钥串：末 64B 是 Ed25519 签名，前 21B 是 claims。
Future<bool> verifyTokenHex(String tokenHex, List<int> publicKey) async {
  final raw = _fromHexOrNull(tokenHex);
  if (raw == null || raw.length != _tokenLen) return false;
  return verifyPublic(
    message: Uint8List.sublistView(raw, 0, _claimsLen),
    signature: Uint8List.sublistView(raw, _claimsLen),
    publicKey: publicKey,
  );
}

// ---------------------------------------------------------------------------
// Claims / 密钥串（与 lib/features/activation/license_key.dart 布局一致）
// ---------------------------------------------------------------------------

/// 21 字节 claims：
///   [0]      版本 = 0x01
///   [1..4]   激活开始   (uint32 大端 UTC 纪元秒)
///   [5..8]   激活截止   (uint32 大端 UTC 纪元秒)
///   [9..12]  授权截止   (uint32 大端 UTC 纪元秒)
///   [13..20] 8 字节随机数（同窗口的密钥由此区分）
/// 密钥串 = 「21B claims + 64B Ed25519 签名」整体大写 hex（170 字符）。
Future<String> signToken({
  required EdKey key,
  required int activationStartSec,
  required int activationEndSec,
  required int expirySec,
  Random? rng,
}) async {
  final claims = _buildClaims(
    activationStartSec,
    activationEndSec,
    expirySec,
    rng,
  );
  final sig = await key.sign(claims);
  final blob = Uint8List(_tokenLen);
  blob.setRange(0, _claimsLen, claims);
  blob.setRange(_claimsLen, _tokenLen, sig);
  return toHexUpper(blob);
}

Uint8List _buildClaims(int rs, int re, int xa, Random? rng) {
  final claims = Uint8List(_claimsLen);
  claims[0] = _claimsVersion;
  _writeUint32(claims, 1, rs);
  _writeUint32(claims, 5, re);
  _writeUint32(claims, 9, xa);
  final rr = rng ?? Random.secure();
  for (var i = 13; i < _claimsLen; i++) {
    claims[i] = rr.nextInt(256);
  }
  return claims;
}

/// 网页 writeUint32：大端写纪元秒，超界抛中文错。
void _writeUint32(Uint8List arr, int at, int v) {
  if (v < 0 || v > uint32Max) {
    throw ArgumentError('时间超出 uint32，须早于 2106-02-07');
  }
  arr[at] = (v >>> 24) & 0xff;
  arr[at + 1] = (v >>> 16) & 0xff;
  arr[at + 2] = (v >>> 8) & 0xff;
  arr[at + 3] = v & 0xff;
}

/// 生成前校验（错误文案与网页一致，返回 null 表示通过）。
String? validateTimes({
  required int activationStartSec,
  required int activationEndSec,
  required int expirySec,
}) {
  if (activationEndSec <= activationStartSec) return '激活截止必须晚于激活开始';
  if (expirySec < activationEndSec) return '授权截止不能早于激活截止';
  for (final v in [activationStartSec, activationEndSec, expirySec]) {
    if (v < 0 || v > uint32Max) return '时间超出 uint32，须早于 2106-02-07';
  }
  return null;
}

String? validateCount(int count) =>
    (count < 1 || count > 200) ? '数量须在 1–200 之间' : null;

/// 本机时区标签，如 UTC+08:00。
String timezoneLabel() {
  final m = -DateTime.now().timeZoneOffset.inMinutes;
  final sign = m < 0 ? '-' : '+';
  final a = m.abs();
  final h = (a ~/ 60).toString().padLeft(2, '0');
  final min = (a % 60).toString().padLeft(2, '0');
  return 'UTC$sign$h:$min';
}

/// 纪元秒 → 本机时间串（对齐网页 fmtLocal）。
String fmtLocal(int epochSec) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
  String pp(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${pp(d.month)}-${pp(d.day)} ${pp(d.hour)}:${pp(d.minute)}:${pp(d.second)}';
}
