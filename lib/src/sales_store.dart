import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 销售文案的本地持久化。
///
/// 营销文案并非敏感数据，这里直接复用现有 secure storage 通道（Keystore /
/// EncryptedSharedPreferences）落盘，避免为一行偏好再引入 shared_preferences
/// 及其安卓插件。下次打开 App 时读取，直接还原上次输入的文案。
class SalesStore {
  SalesStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _kSalesText = 'avp_sales_copy';

  final FlutterSecureStorage _storage;

  Future<String?> load() => _storage.read(key: _kSalesText);

  Future<void> save(String text) => _storage.write(key: _kSalesText, value: text);
}
