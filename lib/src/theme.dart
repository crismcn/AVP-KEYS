import 'package:flutter/material.dart';

/// 配色逐项取自 tools/keygen.html 的深色样式。
class AppColors {
  AppColors._();

  static const Color bg = Color(0xFF000000); // body
  static const Color accent = Color(0xFF00E676); // 强调绿
  static const Color card = Color(0xFF0D0D0D); // section 底色
  static const Color cardBorder = Color(0xFF1E1E1E); // section 边框 / ghost 按钮
  static const Color fieldFill = Color(0xFF141414); // input 底色
  static const Color fieldBorder = Color(0xFF333333); // input 边框
  static const Color textSecondary = Color(0xFF9A9A9A); // .sub / 说明
  static const Color textMuted = Color(0xFFCCCCCC); // label
  static const Color warn = Color(0xFFFFD479); // .warn
  static const Color time = Color(0xFFAAAAAA); // .time
}

/// Material 3 深色主题，主色为强调绿（按钮前景黑，照网页 button 样式）。
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.accent,
    onPrimary: Colors.black,
    surface: AppColors.card,
    onSurface: Colors.white,
    outline: AppColors.cardBorder,
    onSurfaceVariant: AppColors.textSecondary,
    error: const Color(0xFFFF6E6E),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    splashFactory: InkSparkle.splashFactory,
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.accent,
      selectionColor: Color(0x6600E676),
      selectionHandleColor: AppColors.accent,
    ),
    appBarTheme: const AppBarTheme(backgroundColor: AppColors.bg),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: AppColors.cardBorder),
        textStyle: const TextStyle(fontWeight: FontWeight.w500),
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.accent),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.cardBorder),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Color(0xFF1E1E1E),
      contentTextStyle: TextStyle(color: Colors.white, fontSize: 13),
    ),
  );
}
