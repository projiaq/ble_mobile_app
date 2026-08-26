import 'package:flutter/material.dart';

/// 设计令牌:主色/状态色/中性色 + 井下深色(mine-mode)。
/// 浅色与深色主题在 [app_theme.dart] 中组织。
abstract final class AppColors {
  // 主色
  static const primary = Color(0xFF2563EB);
  static const primarySoft = Color(0xFFDBEAFE);
  static const teal = Color(0xFF0D9488);

  // 状态
  static const success = Color(0xFF15803D);
  static const successBg = Color(0xFFDCFCE7);
  static const warning = Color(0xFFB45309);
  static const warningBg = Color(0xFFFEF3C7);
  static const danger = Color(0xFFB91C1C);
  static const dangerBg = Color(0xFFFEE2E2);

  // 中性(浅色)
  static const text = Color(0xFF1F2937);
  static const textMuted = Color(0xFF6B7280);
  static const bg = Color(0xFFEEF1F5);
  static const card = Color(0xFFFFFFFF);
  static const divider = Color(0xFFEEF0F3);
  static const inputBg = Color(0xFFF8FAFC);
  static const inputBorder = Color(0xFFE5E7EB);

  // 井下深色
  static const mineBg = Color(0xFF05070A);
  static const mineCard = Color(0xFF111827);
  static const mineBorder = Color(0xFF334155);
  static const mineText = Color(0xFFF8FAFC);
  static const mineMuted = Color(0xFFCBD5E1);
  static const mineAccent = Color(0xFFFACC15);
}
