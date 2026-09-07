import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../crypto/ed25519_service.dart';
import '../ledger.dart';
import '../pair_store.dart';
import '../theme.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

enum _WhichTime { start, redeemEnd, expiry }

/// 授权时长快捷档（与网页版 tools/keygen.html 一致）：点一下按当前时刻重置三项——
/// 激活开始=现在（整分）、激活截止=+20 分钟、授权截止=现在+所选时长。永久=9999 天。
const List<({int minutes, String label})> _quickPresets = [
  (minutes: 30, label: '30 分钟'),
  (minutes: 60, label: '1 小时'),
  (minutes: 120, label: '2 小时'),
  (minutes: 360, label: '6 小时'),
  (minutes: 7 * 1440, label: '7 天'),
  (minutes: 30 * 1440, label: '30 天'),
  (minutes: 365 * 1440, label: '365 天'),
  (minutes: 9999 * 1440, label: '永久'),
];
/// 快捷档固定短激活窗口（分钟）。
const int _presetRedeemWindowMin = 20;

class _HomePageState extends State<HomePage> {
  /// 与 MainActivity.kt 里的 SAF 文件选择器通道同名。
  static const _fileChannel = MethodChannel('splayer.keygen/file_pick');

  final PairStore _store = PairStore();

  EdKey? _key;
  bool _busy = false;
  bool _revealPrivate = false;

  late DateTime _start;
  late DateTime _redeemEnd;
  late DateTime _expiry;
  int _count = 1;
  List<String> _tokens = const [];

  String? _pairHint; // 密钥对区提示
  String? _paramHint; // 激活参数即时校验
  String? _genErr; // 生成错误

  @override
  void initState() {
    super.initState();
    _applyNowDefaults();
    _restore();
  }

  void _applyNowDefaults() {
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    _redeemEnd = _start.add(const Duration(minutes: 20));
    _expiry = _start.add(const Duration(minutes: 30)); // 授权截止默认 30 分钟后
  }

  int _epoch(DateTime d) => (d.millisecondsSinceEpoch / 1000).floor();

  PairRecord _pairOf(EdKey k) =>
      (privatePkcs8B64: k.pkcs8B64, publicHex: k.publicHex);

  // -------------------------------------------------------------------------
  // 启动恢复
  // -------------------------------------------------------------------------
  Future<void> _restore() async {
    final saved = await _store.load();
    if (!mounted) return;
    if (saved == null) {
      return;
    }
    try {
      final key = await EdKey.fromPkcs8B64(saved.privatePkcs8B64);
      if (!mounted) return;
      final matches =
          saved.publicHex.isEmpty ||
          await key.publicHexMatches(saved.publicHex);
      if (!matches) await _store.save(_pairOf(key)); // 修正落盘
      if (!mounted) return;
      setState(() {
        _key = key;
        _pairHint = matches ? null : '公钥不一致，已按私钥修正';
      });
    } catch (_) {
      await _store.clear();
      if (!mounted) return;
      setState(() => _pairHint = '读取保存的私钥失败，请重新生成');
    }
  }

  // -------------------------------------------------------------------------
  // 密钥对
  // -------------------------------------------------------------------------
  Future<void> _newPair() async {
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        title: const Text(
          '生成新密钥？',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          '旧私钥签发的密钥将无法再用新公钥验证。',
          style: TextStyle(
            fontSize: 13,
            height: 1.6,
            color: AppColors.textMuted,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('生成'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() {
      _busy = true;
      _tokens = const [];
      _genErr = null;
    });
    try {
      final key = await EdKey.generate();
      await _store.save(_pairOf(key));
      if (!mounted) return;
      setState(() {
        _key = key;
        _revealPrivate = false;
        _pairHint = '已生成并加密保存';
      });
    } catch (e) {
      if (mounted) setState(() => _pairHint = '生成失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFromFile() async {
    Object? res;
    try {
      res = await _fileChannel.invokeMethod('pickText');
    } catch (e) {
      if (mounted) showSnack(context, '文件读取失败：$e');
      return;
    }
    if (res is! Map || res['cancelled'] == true) return; // 用户取消
    if (!mounted) return;
    if (res['error'] is String) {
      showSnack(context, res['error'] as String);
      return;
    }
    final text = res['text'];
    if (text is! String || text.trim().isEmpty) {
      showSnack(context, '所选文件是空的');
      return;
    }
    final parsed = PairStore.parse(text);
    if (parsed == null) {
      showSnack(context, '文件里未识别出私钥（PKCS8 base64 或备份文本）');
      return;
    }
    try {
      final key = await EdKey.fromPkcs8B64(parsed.private);
      if (parsed.public != null && parsed.public!.isNotEmpty) {
        if (!await key.publicHexMatches(parsed.public!)) {
          if (mounted) showSnack(context, '公钥与私钥不匹配，已中止导入');
          return;
        }
      }
      await _store.save(_pairOf(key));
      if (!mounted) return;
      setState(() {
        _key = key;
        _revealPrivate = false;
        _tokens = const [];
        _pairHint = null;
      });
      final name = res['name'];
      showSnack(
        context,
        name is String && name.isNotEmpty ? '已导入 $name' : '已导入密钥文件',
      );
    } catch (e) {
      if (mounted) showSnack(context, '文件读取失败：$e');
    }
  }

  // -------------------------------------------------------------------------
  // 激活参数
  // -------------------------------------------------------------------------
  Future<void> _pickTime(_WhichTime which) async {
    final initial = switch (which) {
      _WhichTime.start => _start,
      _WhichTime.redeemEnd => _redeemEnd,
      _WhichTime.expiry => _expiry,
    };
    final picked = await _pickDateTime(context, initial);
    if (picked == null || !mounted) return;
    setState(() {
      switch (which) {
        case _WhichTime.start:
          _start = picked;
        case _WhichTime.redeemEnd:
          _redeemEnd = picked;
        case _WhichTime.expiry:
          _expiry = picked;
      }
      _recheckParams();
    });
  }

  void _recheckParams() {
    _paramHint = validateTimes(
      activationStartSec: _epoch(_start),
      activationEndSec: _epoch(_redeemEnd),
      expirySec: _epoch(_expiry),
    );
  }

  /// 当前「授权截止 − 激活开始」正好等于某快捷档时，高亮它。
  int? get _activePresetMinutes {
    final m = _expiry.difference(_start).inMinutes;
    for (final p in _quickPresets) {
      if (p.minutes == m) return p.minutes;
    }
    return null;
  }

  /// 与网页版 keygen.html 的行为一致：以当前时刻为锚点一次性铺好三项时间。
  void _applyPreset(int minutes) {
    setState(() {
      final now = DateTime.now();
      _start = DateTime(now.year, now.month, now.day, now.hour, now.minute);
      _redeemEnd =
          _start.add(const Duration(minutes: _presetRedeemWindowMin));
      _expiry = _start.add(Duration(minutes: minutes));
      _genErr = null;
      _recheckParams();
    });
  }

  Widget _presetChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.fieldFill,
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.fieldBorder,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 生成
  // -------------------------------------------------------------------------
  Future<void> _generate() async {
    if (_busy) return;
    if (_key == null) {
      showSnack(context, '请先在「1 · 密钥对」生成或导入私钥');
      return;
    }
    final rs = _epoch(_start);
    final re = _epoch(_redeemEnd);
    final xa = _epoch(_expiry);
    final timeErr = validateTimes(
      activationStartSec: rs,
      activationEndSec: re,
      expirySec: xa,
    );
    final countErr = validateCount(_count);
    setState(() {
      _paramHint = timeErr ?? countErr;
      _genErr = null;
    });
    if (timeErr != null || countErr != null) return;

    setState(() => _busy = true);
    try {
      // 纯 Dart Ed25519 在主 isolate 上签名：先让出一次事件循环，让按钮里的
      // 「正在生成…」loading 真正画出来；长批中再周期性让位，避免整段卡住。
      await Future<void>.delayed(const Duration(milliseconds: 16));
      final rows = <String>[];
      for (var i = 0; i < _count; i++) {
        rows.add(
          await signToken(
            key: _key!,
            activationStartSec: rs,
            activationEndSec: re,
            expirySec: xa,
          ),
        );
        if (_count > 1 && (i + 1) % 8 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      if (!mounted) return;
      setState(() => _tokens = rows);
    } catch (e) {
      if (mounted) setState(() => _genErr = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyLedger() async {
    if (_tokens.isEmpty) return;
    final md = markdownLedger(
      activationStartSec: _epoch(_start),
      activationEndSec: _epoch(_redeemEnd),
      expirySec: _epoch(_expiry),
      tokens: _tokens,
    );
    await copyText(context, md, message: '已复制 Markdown 台账');
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final key = _key;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
          children: [
            _header(),
            const SizedBox(height: 14),
            SectionCard(title: '1 · 密钥对', child: _buildPairCard(key)),
            SectionCard(title: '2 · 激活参数', child: _buildParamCard()),
            SectionCard(title: '3 · 生成清单', child: _buildGenCard(key)),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 60,
          height: 60,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.black,
          ),
          child: Image.asset('assets/logo.png', fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SKEY 密钥生成器',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPairCard(EdKey? key) {
    final privateShown =
        key != null && (_revealPrivate || key.pkcs8B64.length <= 16);
    final privateText = !_revealPrivate && key != null
        ? _maskPrivate(key.pkcs8B64)
        : (key?.pkcs8B64 ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _newPair,
                icon: const Icon(Icons.fingerprint, size: 18),
                label: const Text('生成新密钥'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _importFromFile,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('导入密钥'),
              ),
            ),
          ],
        ),
        if (key != null) ...[
          const SizedBox(height: 12),
          AppField(
            label: '私钥（PKCS8）',
            text: privateText,
            maxLines: privateShown ? 3 : 1,
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  tooltip: _revealPrivate ? '隐藏' : '显示',
                  icon: Icon(
                    _revealPrivate
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _revealPrivate = !_revealPrivate),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  tooltip: '复制私钥',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () =>
                      copyText(context, key.pkcs8B64, message: '私钥已复制'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          AppField(
            label: '公钥（hex）',
            text: key.publicHex,
            maxLines: 2,
            action: IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              tooltip: '复制公钥',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () =>
                  copyText(context, key.publicHex, message: '公钥已复制'),
            ),
          ),
        ],
        if (_pairHint != null) ...[
          const SizedBox(height: 8),
          Text(
            _pairHint!,
            style: const TextStyle(fontSize: 12, color: AppColors.warn),
          ),
        ],
      ],
    );
  }

  String _maskPrivate(String b64) {
    if (b64.length <= 20) return b64;
    return '${b64.substring(0, 10)}…${b64.substring(b64.length - 10)}';
  }

  Widget _paramTile({
    required _WhichTime which,
    required String title,
    required DateTime value,
    IconData icon = Icons.schedule,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _pickTime(which),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.fieldFill,
          border: Border.all(color: AppColors.fieldBorder),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Text(
              fmtDateTime(value),
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParamCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '授权时长',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in _quickPresets)
              _presetChip(
                label: p.label,
                selected: p.minutes == _activePresetMinutes,
                onTap: () => _applyPreset(p.minutes),
              ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          '点档位即按当前时刻重置：激活开始=现在，可激活窗口 +20 分钟，授权截止=现在+时长（可再点下面各行微调）',
          style: TextStyle(
            fontSize: 10,
            height: 1.5,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 12),
        _paramTile(
          which: _WhichTime.start,
          title: '激活开始',
          value: _start,
          icon: Icons.play_circle_outline,
        ),
        _paramTile(
          which: _WhichTime.redeemEnd,
          title: '激活截止',
          value: _redeemEnd,
          icon: Icons.login,
        ),
        _paramTile(
          which: _WhichTime.expiry,
          title: '授权截止',
          value: _expiry,
          icon: Icons.hourglass_bottom,
        ),
        if (_paramHint != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _paramHint!,
              style: const TextStyle(fontSize: 12, color: AppColors.warn),
            ),
          ),
        const SizedBox(height: 8),
        CountStepper(
          value: _count,
          onChanged: (v) => setState(() => _count = v),
        ),
      ],
    );
  }

  Widget _buildGenCard(EdKey? key) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: (_busy || key == null) ? null : _generate,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Icon(Icons.key_rounded, size: 18),
            label: Text(_busy ? '正在生成…' : '生成密钥'),
          ),
        ),
        if (_genErr != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '生成失败：$_genErr',
              style: const TextStyle(fontSize: 12, color: AppColors.warn),
            ),
          ),
        if (_tokens.isNotEmpty) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _copyLedger,
            icon: const Icon(Icons.table_chart_outlined, size: 18),
            label: const Text('复制台账'),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _tokens.length; i++) _keyTile(i, _tokens[i]),
        ],
      ],
    );
  }

  Widget _keyTile(int index, String token) {
    final window =
        '激活 ${fmtLocal(_epoch(_start))} → ${fmtLocal(_epoch(_redeemEnd))}'
        '　授权至 ${fmtLocal(_epoch(_expiry))}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.fieldFill,
        border: Border.all(color: AppColors.fieldBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '#${index + 1}',
              style: const TextStyle(
                color: AppColors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  window,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.time,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  formatKey(token),
                  style: kMono.copyWith(color: Colors.white, fontSize: 10.5),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '复制密钥',
            icon: const Icon(Icons.copy, size: 18),
            color: AppColors.accent,
            onPressed: () => copyText(
              context,
              '激活密钥：$token',
              message: '#${index + 1} 已复制',
            ),
          ),
        ],
      ),
    );
  }
}

/// 一次滚出「日期 + 时间」（单步底部滚轮，替代原先先日期后时间的两次弹层）。
Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) {
  final minDate = DateTime(2000);
  final maxDate = DateTime(2106, 2, 7);
  var sel = initial.isBefore(minDate)
      ? minDate
      : (initial.isAfter(maxDate) ? maxDate : initial);
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(width: 14),
                const Text(
                  '滚动选择日期与时间（最晚 2106-02-07）',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, sel),
                  child: const Text('完成'),
                ),
              ],
            ),
            CupertinoTheme(
              data: const CupertinoThemeData(
                brightness: Brightness.dark,
                primaryColor: AppColors.accent,
              ),
              child: SizedBox(
                height: 216,
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.dateAndTime,
                  use24hFormat: true,
                  initialDateTime: sel,
                  minimumDate: minDate,
                  maximumDate: maxDate,
                  onDateTimeChanged: (d) => sel = d,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
