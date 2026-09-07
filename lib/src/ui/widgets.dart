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
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          child,
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
