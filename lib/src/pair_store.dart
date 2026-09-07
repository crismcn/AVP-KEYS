import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ledger.dart' show parseBackupText;

/// 一组成对的私钥/公钥（私钥 = PKCS8 base64，同网页格式）。
typedef PairRecord = ({String privatePkcs8B64, String publicHex});

/// 私钥落盘：Android Keystore / EncryptedSharedPreferences，仅应用内可读。
class PairStore {
  PairStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _kPrivate = 'avp_private_pkcs8';
  static const _kPublic = 'avp_public_hex';

  final FlutterSecureStorage _storage;

  Future<PairRecord?> load() async {
    final priv = await _storage.read(key: _kPrivate);
    if (priv == null || priv.isEmpty) return null;
    final pub = await _storage.read(key: _kPublic) ?? '';
    return (privatePkcs8B64: priv, publicHex: pub);
  }

  Future<void> save(PairRecord pair) async {
    await _storage.write(key: _kPrivate, value: pair.privatePkcs8B64);
    await _storage.write(key: _kPublic, value: pair.publicHex);
  }

  Future<void> clear() async {
    await _storage.delete(key: _kPrivate);
    await _storage.delete(key: _kPublic);
  }

  /// 解析文件/粘贴内容（备份 txt 或裸 base64）。
  static ({String private, String? public})? parse(String text) =>
      parseBackupText(text);
}
