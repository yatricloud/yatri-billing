import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';

/// Typography system — Plus Jakarta Sans (GT Walsheim / Fold Money standard) + JetBrains Mono (financial figures)
abstract final class AppTypography {
  static TextStyle get _body => GoogleFonts.plusJakartaSans(
        textStyle: const TextStyle(color: CbTokens.ink),
      );

  static TextStyle get _display => GoogleFonts.plusJakartaSans(
        textStyle: const TextStyle(color: CbTokens.ink),
      );

  static TextStyle get _mono => GoogleFonts.jetBrainsMono(
        textStyle: const TextStyle(color: CbTokens.ink),
      );

  static TextStyle displayLg([Color? color]) => _display.copyWith(
        fontSize: 48,
        fontWeight: FontWeight.w700,
        height: 1.05,
        letterSpacing: -1.2,
        color: color ?? CbTokens.ink,
      );

  static TextStyle displayMd([Color? color]) => _display.copyWith(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        height: 1.1,
        letterSpacing: -0.8,
        color: color ?? CbTokens.ink,
      );

  static TextStyle displaySm([Color? color]) => _display.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.15,
        letterSpacing: -0.5,
        color: color ?? CbTokens.ink,
      );

  static TextStyle titleLg([Color? color]) => _display.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: -0.3,
        color: color ?? CbTokens.ink,
      );

  static TextStyle titleMd([Color? color]) => _body.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.33,
        color: color ?? CbTokens.ink,
      );

  static TextStyle titleSm([Color? color]) => _body.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.25,
        color: color ?? CbTokens.ink,
      );

  static TextStyle bodyMd([Color? color]) => _body.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color ?? CbTokens.body,
      );

  static TextStyle bodyStrong([Color? color]) => _body.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.5,
        color: color ?? CbTokens.bodyStrong,
      );

  static TextStyle bodySm([Color? color]) => _body.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color ?? CbTokens.body,
      );

  static TextStyle caption([Color? color]) => _body.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color ?? CbTokens.muted,
      );

  static TextStyle captionStrong([Color? color]) => _body.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.5,
        color: color ?? CbTokens.ink,
      );

  static TextStyle numberDisplay([Color? color]) => _mono.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: color ?? CbTokens.ink,
      );

  static TextStyle button([Color? color]) => _body.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.15,
        letterSpacing: -0.1,
        color: color ?? CbTokens.onPrimary,
      );

  static TextStyle navLink([Color? color]) => _body.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.4,
        color: color ?? CbTokens.ink,
      );

  static TextTheme get textTheme => TextTheme(
        displayLarge: displayLg(),
        displayMedium: displayMd(),
        displaySmall: displaySm(),
        headlineLarge: titleLg(),
        headlineMedium: titleMd(),
        headlineSmall: titleSm(),
        titleLarge: titleMd(),
        titleMedium: titleSm(),
        titleSmall: titleSm(),
        bodyLarge: bodyMd(CbTokens.ink),
        bodyMedium: bodyMd(),
        bodySmall: bodySm(),
        labelLarge: button(CbTokens.ink),
        labelMedium: captionStrong(),
        labelSmall: caption(),
      );
}
