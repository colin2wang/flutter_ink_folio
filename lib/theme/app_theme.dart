import 'package:flutter/material.dart';

/// 墨水屏全局灰阶主题。
/// 规则：只用黑白灰、零阴影（elevation=0）、零涟漪（NoSplash）、零动画。
class AppTheme {
  AppTheme._();

  // 灰阶色板（16 阶里挑 6 阶，留足对比）
  static const gray0 = Color(0xFFFFFFFF); // 纸面
  static const gray1 = Color(0xFFF2F2F2); // 卡片/分区
  static const gray3 = Color(0xFFBDBDBD); // 分隔线
  static const gray5 = Color(0xFF757575); // 次级文字
  static const gray7 = Color(0xFF333333); // 主文字
  static const gray9 = Color(0xFF111111); // 强调/夜间纸面文字

  static ThemeData light() => _base(
        scaffold: gray0,
        surface: gray1,
        onSurface: gray7,
        divider: gray3,
        primary: gray9,
        onPrimary: gray0,
        brightness: Brightness.light,
      );

  static ThemeData dark() => _base(
        scaffold: const Color(0xFF0E0E0E),
        surface: const Color(0xFF1C1C1C),
        onSurface: gray3,
        divider: const Color(0xFF2E2E2E),
        primary: gray0,
        onPrimary: const Color(0xFF111111),
        brightness: Brightness.dark,
      );

  static ThemeData _base({
    required Color scaffold,
    required Color surface,
    required Color onSurface,
    required Color divider,
    required Color primary,
    required Color onPrimary,
    required Brightness brightness,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: onPrimary,
        secondary: onSurface,
        onSecondary: scaffold,
        error: onSurface,
        onError: scaffold,
        surface: surface,
        onSurface: onSurface,
      ),
      scaffoldBackgroundColor: scaffold,
      splashFactory: NoSplash.splashFactory, // 禁涟漪
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      fontFamily: null, // 用系统默认，等宽灰阶更稳
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: onSurface,
        elevation: 0, // 禁阴影
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
      ),
      dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: divider),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: divider),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: onSurface,
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      iconTheme: IconThemeData(color: onSurface, size: 22),
      listTileTheme: ListTileThemeData(
        iconColor: onSurface,
        textColor: onSurface,
      ),
    );
  }
}
