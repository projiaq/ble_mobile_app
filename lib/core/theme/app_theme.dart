import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 应用主题:浅色(默认)+ 井下深色(高对比)。
abstract final class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary);
    return ThemeData(
      colorScheme: scheme.copyWith(
        primary: AppColors.primary,
        surface: AppColors.card,
      ),
      scaffoldBackgroundColor: AppColors.bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.card,
        foregroundColor: AppColors.text,
        elevation: 0,
        centerTitle: false,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.mineAccent,
      brightness: Brightness.dark,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.mineBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.mineCard,
        foregroundColor: AppColors.mineText,
        elevation: 0,
        centerTitle: false,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.mineBorder),
    );
  }
}
