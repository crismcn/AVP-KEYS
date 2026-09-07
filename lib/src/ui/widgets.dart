import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

const TextStyle kMono = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['Roboto Mono', 'Courier New', 'Courier'],
  fontSize: 11.5,
  height: 1.5,
  letterSpacing: 0.1,
);

void showSnack(BuildContext context, String msg) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.removeCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(msg)));
}

Future<void> copyText(BuildContext context, String text, {String? message}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showSnack(context, message ?? '已复制');
}

String fmtDateTime(DateTime dt) {
  String p(int v) => v.toString().padLeft(2, '0');
  return '${dt.year}-${p(dt.month)}-${p(dt.day)} ${p(dt.hour)}:${p(dt.minute)}';
}

/// 卡片分节（对应网页 section + h2）。
///
/// 标题整行可点击：折叠/展开卡片（右侧箭头指示当前状态）。折叠状态由外部持有
/// （[expanded]/[onToggle]），便于页面层做本地持久化；收起时 [child] 不参与布局，
/// [trailing]（如刷新按钮）仅随标题行保留。
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    required this.expanded,
    required this.onToggle,
    this.trailing,
  });

  final String title;
  final Widget child;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.fromLTRB(14, 6, 6, expanded ? 14 : 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 6, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ),
                  ?trailing,
                  const SizedBox(width: 4),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 4),
            child,
          ],
        ],
      ),
    );
  }
}

/// 只读等宽字段框（私钥 / 公钥展示）。
class AppField extends StatelessWidget {
  const AppField({
    super.key,
    required this.label,
    required this.text,
    this.action,
    this.maxLines = 3,
  });

  final String label;
  final String text;
  final Widget? action; // 右侧复制按钮等
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
            ?action,
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.fieldFill,
            border: Border.all(color: AppColors.fieldBorder),
            borderRadius: BorderRadius.circular(6),
          ),
          child: SelectableText(
            text.isEmpty ? '（空）' : text,
            style: kMono.copyWith(
              color: text.isEmpty ? AppColors.textMuted : Colors.white,
            ),
            maxLines: maxLines,
          ),
        ),
      ],
    );
  }
}

/// 数量步进（1–200）。
class CountStepper extends StatelessWidget {
  const CountStepper({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget step(int delta) {
      return InkWell(
        onTap: () => onChanged((value + delta).clamp(1, 200)),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.cardBorder,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(delta < 0 ? '−' : '+',
              style: const TextStyle(color: Colors.white, fontSize: 18)),
        ),
      );
    }

    return Row(
      children: [
        const Text('数量',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
        const SizedBox(width: 12),
        step(-1),
        Container(
          width: 56,
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.fieldFill,
            border: Border.all(color: AppColors.fieldBorder),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('$value',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ),
        step(1),
        const Spacer(),
      ],
    );
  }
}
