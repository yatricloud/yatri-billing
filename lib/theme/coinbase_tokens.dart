import 'package:flutter/material.dart';

/// Yatri Cloud design tokens — aligned to DESIGN.md
/// Primary brand blue: #007CFF (hsl 210 100% 50%)
/// Dark hover: #0062CC (hsl 210 100% 40%)
/// Canvas: #F8FAFC (slate-50), Cards: #FFFFFF, Borders: #E2E8F0 (slate-200)
abstract final class CbTokens {
  // ── Brand Blue (Yatri Cloud #007CFF) ──────────────────────────
  static const primary = Color(0xFF007CFF); // Yatri brand blue
  static const primaryActive = Color(0xFF0062CC); // hover/active
  static const primaryDisabled = Color(0xFF93C5FD); // disabled state
  static const primaryTint = Color(0xFFEFF6FF); // soft blue-50 tint
  static const primaryTintMid = Color(0xFFDBEAFE); // blue-100 for banners

  // ── Ink & Text ────────────────────────────────────────────────
  static const ink = Color(0xFF0F172A); // slate-900 primary text
  static const body = Color(0xFF334155); // slate-700 body
  static const bodyStrong = Color(0xFF1E293B); // slate-800 strong body
  static const muted = Color(0xFF64748B); // slate-500 secondary/caption
  static const mutedSoft = Color(0xFF94A3B8); // slate-400 placeholder
  static const inverse = Color(0xFFFFFFFF); // on-dark

  // ── Surfaces ──────────────────────────────────────────────────
  static const canvas = Color(0xFFFFFFFF); // pure white surface
  static const background = Color(0xFFF8FAFC); // slate-50 page canvas
  static const surface = Color(0xFFFFFFFF); // card surface
  static const surfaceSoft = Color(0xFFF8FAFC); // softer surface
  static const surfaceStrong = Color(0xFFF1F5F9); // slate-100
  static const surfaceDark = Color(0xFF1E293B); // slate-800 dark surface
  static const surfaceDarkElevated = Color(0xFF0F172A); // slate-900

  // ── Borders & Dividers ────────────────────────────────────────
  static const hairline = Color(0xFFE2E8F0); // slate-200 borders
  static const hairlineSoft = Color(0xFFE5E7EB); // gray-200 compat
  static const borderDefault = Color(0xFFCBD5E1); // slate-300

  // ── On-colors ─────────────────────────────────────────────────
  static const onPrimary = Color(0xFFFFFFFF);
  static const onDark = Color(0xFFFFFFFF);
  static const onDarkSoft = Color(0xFF94A3B8); // slate-400

  // ── Semantic / Status ─────────────────────────────────────────
  static const semanticUp = Color(0xFF10B981); // emerald-500 success
  static const semanticDown = Color(0xFFEF4444); // red-500 destructive
  static const semanticDownDark = Color(0xFFDC2626); // red-600 pressed
  static const accentYellow = Color(0xFFF59E0B); // amber-500
  static const accentTint = Color(0xFFEFF6FF); // blue-50
  static const blue = Color(0xFF007CFF); // alias for primary
  static const green = Color(0xFF10B981); // emerald-500

  // ── Radius Scale ──────────────────────────────────────────────
  static const radiusXs = 6.0;   // micro — inputs, tags
  static const radiusSm = 10.0;  // buttons, small cards
  static const radiusMd = 12.0;  // cards
  static const radiusLg = 16.0;  // large cards
  static const radiusXl = 20.0;  // modals, dialogs
  static const radiusPill = 9999.0; // pills, avatars

  // ── Spacing Scale (4/8 system) ────────────────────────────────
  static const spaceXxs = 4.0;
  static const spaceXs = 8.0;
  static const spaceSm = 12.0;
  static const spaceBase = 16.0;
  static const spaceMd = 24.0;
  static const spaceLg = 32.0;
  static const spaceXl = 48.0;
  static const spaceXxl = 64.0;
  static const spaceSection = 96.0;

  // ── Layout ────────────────────────────────────────────────────
  static const maxContentWidth = 1280.0;
  static const navHeight = 64.0;
  static const sidebarExpanded = 250.0;
  static const sidebarCollapsed = 72.0;

  // ── Shadows ───────────────────────────────────────────────────
  static const cardShadow = BoxShadow(
    color: Color(0x0A000000), // 4% black — very subtle
    blurRadius: 12,
    offset: Offset(0, 3),
  );
  static const shadow1 = BoxShadow(
    color: Color(0x0F000000), // 6% black
    blurRadius: 8,
    offset: Offset(0, 2),
  );
  static const shadow2 = BoxShadow(
    color: Color(0x14000000), // 8% black — modals
    blurRadius: 24,
    offset: Offset(0, 8),
  );

  // ── Animation ─────────────────────────────────────────────────
  static const durationFast = Duration(milliseconds: 100);
  static const durationNormal = Duration(milliseconds: 200);
  static const durationSlow = Duration(milliseconds: 350);
  static const curveDefault = Curves.easeOutCubic;
}
