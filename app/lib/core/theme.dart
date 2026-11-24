import 'package:flutter/material.dart';

/// 全局配色：沿用设计稿的绿色品牌色与 Apple 浅色风格。
class AppColors {
  static const brand = Color(0xFF0BA85C);
  static const brandDeep = Color(0xFF02743B);
  static const brandSoft = Color(0xFFE9FBF1);
  static const ink = Color(0xFF0F172A);
  static const ink2 = Color(0xFF475569);
  static const ink3 = Color(0xFF94A3B8);
  static const line = Color(0xFFE8EBF0);
  static const page = Color(0xFFF1F3F6);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF7F8FA);
  static const warn = Color(0xFFB45309);
  static const warnSoft = Color(0xFFFEF3C7);
  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0xFFFEE2E2);
}

/// 构建应用主题。
///
/// 返回：Material 3 浅色主题，统一 AppBar、输入框、按钮与底部导航样式。
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
  ).copyWith(
    primary: AppColors.brand,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.page,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.page,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.brandSoft,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? AppColors.brandDeep : AppColors.ink3,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 22,
          color: selected ? AppColors.brandDeep : AppColors.ink3,
        );
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.brandDeep,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: AppColors.surface),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: TextStyle(color: Colors.white, fontSize: 13),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1),
  );
}

/// 统一的输入框装饰。
///
/// 参数：[hint] 占位文案；[suffix] 后缀组件。
/// 返回：带浅灰底与圆角边框的 InputDecoration。
InputDecoration appInput({
  String? hint,
  String? label,
  Widget? suffix,
  Widget? prefix,
}) {
  return InputDecoration(
    hintText: hint,
    labelText: label,
    suffixIcon: suffix,
    prefixIcon: prefix,
    filled: true,
    fillColor: AppColors.surface2,
    hintStyle: const TextStyle(color: AppColors.ink3, fontSize: 14),
    labelStyle: const TextStyle(color: AppColors.ink2, fontSize: 14),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.brand, width: 1.4),
    ),
  );
}

/// 统一的时间格式化：今天只显示时分，其余显示日期。
///
/// 参数：[ms] 毫秒时间戳。
/// 返回：可读时间字符串。
String formatTime(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  if (sameDay) return '$hh:$mm';
  return '${t.month}/${t.day} $hh:$mm';
}
