import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 卡片折叠状态的本地持久化。
///
/// 折叠与否属于轻量 UI 偏好，复用现有 secure storage 通道落盘即可，避免再引入
/// shared_preferences 插件。整体存成一个 JSON 数组（一次读、一次写），由页面层
/// 持有内存态、在切换时整体覆盖写，天然规避 read-modify-write 的并发竞态。
class CardPrefs {
  CardPrefs({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'avp_cards_collapsed';

  final FlutterSecureStorage _storage;

  /// 恢复已折叠卡片的 id 集合（空 = 全部展开）。
  Future<Set<String>> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final list = (jsonDecode(raw) as List).cast<String>();
      return list.toSet();
    } catch (_) {
      return const {};
    }
  }

  /// 整体覆盖保存当前折叠集合；空集合时清空记录。
  Future<void> save(Set<String> collapsedIds) async {
    if (collapsedIds.isEmpty) {
      await _storage.delete(key: _key);
      return;
    }
    final sorted = collapsedIds.toList()..sort();
    await _storage.write(key: _key, value: jsonEncode(sorted));
  }
}
