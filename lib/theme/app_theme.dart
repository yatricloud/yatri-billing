import 'package:flutter/material.dart';
import 'package:invoiso/theme/app_typography.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';

class AppTheme {
  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: CbTokens.primary,
      onPrimary: CbTokens.onPrimary,
      secondary: CbTokens.surfaceStrong,
      onSecondary: CbTokens.ink,
      surface: CbTokens.canvas,
      onSurface: CbTokens.ink,
      error: CbTokens.semanticDown,
      onError: CbTokens.onPrimary,
      outline: CbTokens.hairline,
      outlineVariant: CbTokens.hairlineSoft,
      surfaceContainer: CbTokens.canvas,
      surfaceContainerHighest: CbTokens.surfaceSoft,
      onSurfaceVariant: CbTokens.muted,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: CbTokens.primary,
      // Page canvas is slate-50 (#F8FAFC) per Yatri Cloud DESIGN.md
      scaffoldBackgroundColor: CbTokens.background,
      canvasColor: CbTokens.canvas,
      dividerColor: CbTokens.hairline,
      splashColor: const Color(0xFFE2E8F0), // slate-200
      highlightColor: const Color(0xFFF1F5F9), // slate-100
      hoverColor: const Color(0xFFF1F5F9),
      colorScheme: scheme,
      textTheme: AppTypography.textTheme,
      primaryTextTheme: AppTypography.textTheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: CbTokens.canvas,
        foregroundColor: CbTokens.ink,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTypography.titleMd(CbTokens.ink),
        iconTheme: const IconThemeData(color: CbTokens.ink, size: 22),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: CbTokens.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CbTokens.radiusLg),
          side: const BorderSide(color: CbTokens.hairline, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: CbTokens.canvas,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CbTokens.radiusXl),
        ),
        titleTextStyle: AppTypography.titleMd(),
        contentTextStyle: AppTypography.bodyMd(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CbTokens.canvas,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: AppTypography.bodyMd(CbTokens.mutedSoft),
        labelStyle: AppTypography.bodySm(CbTokens.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CbTokens.radiusSm),
          borderSide: const BorderSide(color: CbTokens.hairline, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CbTokens.radiusSm),
          borderSide: const BorderSide(color: CbTokens.hairline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CbTokens.radiusSm),
          borderSide: const BorderSide(color: CbTokens.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CbTokens.radiusSm),
          borderSide: const BorderSide(color: CbTokens.semanticDown, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          // SOLID vibrant blue — no transparency/pale tints per DESIGN.md strict rule
          backgroundColor: CbTokens.primary,
          foregroundColor: CbTokens.onPrimary,
          disabledBackgroundColor: CbTokens.primaryDisabled,
          disabledForegroundColor: CbTokens.onPrimary,
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CbTokens.radiusSm),
          ),
          textStyle: AppTypography.button(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: CbTokens.ink,
          backgroundColor: Colors.white,
          side: const BorderSide(color: CbTokens.hairline, width: 1),
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CbTokens.radiusSm),
          ),
          textStyle: AppTypography.button(CbTokens.ink),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: CbTokens.primary,
          textStyle: AppTypography.button(CbTokens.primary),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: CbTokens.primary,
        foregroundColor: CbTokens.onPrimary,
        elevation: 0,
        shape: StadiumBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: CbTokens.surfaceDark,
        contentTextStyle: AppTypography.bodySm(CbTokens.onDark),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CbTokens.radiusMd),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: CbTokens.surfaceStrong,
        labelStyle: AppTypography.captionStrong(),
        shape: const StadiumBorder(),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      dividerTheme: const DividerThemeData(
        color: CbTokens.hairline,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        titleTextStyle: AppTypography.titleSm(),
        subtitleTextStyle: AppTypography.bodySm(),
        iconColor: CbTokens.muted,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: CbTokens.surfaceDark,
          borderRadius: BorderRadius.circular(CbTokens.radiusSm),
        ),
        textStyle: AppTypography.caption(CbTokens.onDark),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: CbTokens.primary,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: CbTokens.primary,
        unselectedLabelColor: CbTokens.muted,
        indicatorColor: CbTokens.primary,
        labelStyle: AppTypography.navLink(CbTokens.primary),
        unselectedLabelStyle: AppTypography.navLink(CbTokens.muted),
        dividerColor: CbTokens.hairline,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: CbTokens.canvas,
        selectedIconTheme: const IconThemeData(color: CbTokens.primary),
        unselectedIconTheme: const IconThemeData(color: CbTokens.muted),
        selectedLabelTextStyle: AppTypography.captionStrong(CbTokens.primary),
        unselectedLabelTextStyle: AppTypography.caption(CbTokens.muted),
      ),
    );
  }

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: CbTokens.primary,
      onPrimary: CbTokens.onPrimary,
      secondary: CbTokens.surfaceDarkElevated,
      onSecondary: CbTokens.onDark,
      surface: CbTokens.surfaceDark,
      onSurface: CbTokens.onDark,
      error: CbTokens.semanticDown,
      onError: CbTokens.onPrimary,
      outline: Color(0xFF2A2D33),
      outlineVariant: Color(0xFF1E2126),
      surfaceContainer: CbTokens.surfaceDarkElevated,
      surfaceContainerHighest: CbTokens.surfaceDark,
      onSurfaceVariant: CbTokens.onDarkSoft,
    );

    return light.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: CbTokens.surfaceDark,
      canvasColor: CbTokens.surfaceDark,
      dividerColor: const Color(0xFF2A2D33),
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: CbTokens.surfaceDark,
        foregroundColor: CbTokens.onDark,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTypography.titleMd(CbTokens.onDark),
        iconTheme: const IconThemeData(color: CbTokens.onDark, size: 22),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: CbTokens.surfaceDarkElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CbTokens.radiusLg),
          side: const BorderSide(color: Color(0xFF2A2D33), width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: CbTokens.surfaceDarkElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CbTokens.radiusXl),
        ),
        titleTextStyle: AppTypography.titleMd(CbTokens.onDark),
        contentTextStyle: AppTypography.bodyMd(CbTokens.onDarkSoft),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CbTokens.surfaceDarkElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: AppTypography.bodyMd(CbTokens.onDarkSoft),
        labelStyle: AppTypography.bodySm(CbTokens.onDarkSoft),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CbTokens.radiusMd),
          borderSide: const BorderSide(color: Color(0xFF2A2D33), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CbTokens.radiusMd),
          borderSide: const BorderSide(color: Color(0xFF2A2D33), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CbTokens.radiusMd),
          borderSide: const BorderSide(color: CbTokens.primary, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: CbTokens.surfaceDarkElevated,
        contentTextStyle: AppTypography.bodySm(CbTokens.onDark),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CbTokens.radiusMd),
        ),
      ),
    );
  }
}
