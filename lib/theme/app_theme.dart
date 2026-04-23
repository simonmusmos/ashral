import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Color tokens ──────────────────────────────────────────────────────────────

abstract final class AppColors {
  // Backgrounds — Apple dark system palette
  static const bgDeep     = Color(0xFF000000);   // True black (OLED optimized)
  static const bgBase     = Color(0xFF111113);   // Primary content layer
  static const bgElevated = Color(0xFF1C1C1E);   // Apple primary grouped background
  static const bgOverlay  = Color(0xFF2C2C2E);   // Apple secondary grouped background

  // Separators — Apple-style translucent white
  static const border       = Color(0x26FFFFFF); // white 15%
  static const borderSubtle = Color(0x14FFFFFF); // white 8%

  // Labels — Apple dark label hierarchy
  static const textPrimary   = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF98989E); // Apple secondary label
  static const textMuted     = Color(0xFF636366); // Apple tertiary label

  // Status: running / active — Apple system green
  static const running       = Color(0xFF30D158);
  static const runningBg     = Color(0x1430D158); // 8% opacity
  static const runningBorder = Color(0x2630D158); // 15% opacity

  // Status: success / completed
  static const success       = Color(0xFF30D158);
  static const successBg     = Color(0x0A30D158);
  static const successBorder = Color(0x1A30D158);

  // Status: active/in-progress — indigo
  static const active       = Color(0xFF6E6CF8);
  static const activeBg     = Color(0x0F6E6CF8);
  static const activeBorder = Color(0x1A6E6CF8);

  // Status: waiting — Apple system orange
  static const waiting       = Color(0xFFFF9F0A);
  static const waitingBg     = Color(0x14FF9F0A);
  static const waitingBorder = Color(0x26FF9F0A);

  // Status: error / failed — Apple system red
  static const error       = Color(0xFFFF453A);
  static const errorBg     = Color(0x14FF453A);
  static const errorBorder = Color(0x26FF453A);

  // Status: pending
  static const pending   = Color(0xFF48484A);
  static const pendingBg = Color(0xFF1C1C1E);

  // AI / brand accent — warm amber
  static const ai   = Color(0xFFFF9F0A);
  static const aiBg = Color(0x14FF9F0A);

  // Terminal text
  static const terminalText    = Color(0xFF98E268); // lime
  static const terminalCmd     = Color(0xFF64D2FF); // sky blue
  static const terminalWarn    = Color(0xFFFF9F0A);
  static const terminalErr     = Color(0xFFFF453A);
  static const terminalSuccess = Color(0xFF30D158);

  // Diff
  static const diffAdd    = Color(0xFF30D158);
  static const diffRemove = Color(0xFFFF453A);
}

// ── Text style helpers ─────────────────────────────────────────────────────────

abstract final class AppText {
  /// Bricolage Grotesque — hero moments: session title, stat numbers
  static TextStyle display({
    double size = 22,
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.textPrimary,
    double? letterSpacing,
  }) =>
      GoogleFonts.bricolageGrotesque(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing ?? -0.4,
      );

  /// Inter — all UI text (SF Pro equivalent via Google Fonts)
  static TextStyle ui({
    double size = 15,
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.textPrimary,
    double? letterSpacing,
    double? height,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  /// IBM Plex Mono — terminal, paths, counts, labels
  static TextStyle mono({
    double size = 13,
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.textSecondary,
    double? letterSpacing,
    double? height,
  }) =>
      GoogleFonts.ibmPlexMono(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  /// Section label — UPPERCASE, muted, monospaced
  static TextStyle sectionLabel() => mono(
        size: 10,
        weight: FontWeight.w600,
        color: AppColors.textMuted,
        letterSpacing: 1.2,
      );
}

// ── Status colors helper ───────────────────────────────────────────────────────

typedef StatusPalette = ({Color dot, Color bg, Color border, Color text});

abstract final class AppStatus {
  static StatusPalette palette(String status) {
    switch (status.toLowerCase()) {
      case 'running':
      case 'active':
        return (
          dot: AppColors.running,
          bg: AppColors.runningBg,
          border: AppColors.runningBorder,
          text: AppColors.running,
        );
      case 'completed':
      case 'done':
        return (
          dot: AppColors.success,
          bg: AppColors.successBg,
          border: AppColors.successBorder,
          text: AppColors.success,
        );
      case 'waiting_for_input':
      case 'waiting':
      case 'paused':
        return (
          dot: AppColors.waiting,
          bg: AppColors.waitingBg,
          border: AppColors.waitingBorder,
          text: AppColors.waiting,
        );
      case 'error':
      case 'failed':
        return (
          dot: AppColors.error,
          bg: AppColors.errorBg,
          border: AppColors.errorBorder,
          text: AppColors.error,
        );
      case 'terminated':
        return (
          dot: AppColors.textSecondary,
          bg: AppColors.bgElevated,
          border: AppColors.border,
          text: AppColors.textSecondary,
        );
      default:
        return (
          dot: AppColors.pending,
          bg: AppColors.pendingBg,
          border: AppColors.border,
          text: AppColors.textSecondary,
        );
    }
  }

  static bool isLive(String status) {
    final s = status.toLowerCase();
    return s == 'running' || s == 'active';
  }
}

// ── Theme builder ──────────────────────────────────────────────────────────────

abstract final class AshralTheme {
  static ThemeData build() {
    final interBase = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bgDeep,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.textPrimary,
        onPrimary: AppColors.bgDeep,
        surface: AppColors.bgBase,
        onSurface: AppColors.textPrimary,
        outline: AppColors.border,
        error: AppColors.error,
        onError: AppColors.textPrimary,
      ),
      textTheme: interBase.copyWith(
        bodyMedium: interBase.bodyMedium?.copyWith(color: AppColors.textSecondary),
        bodySmall: interBase.bodySmall?.copyWith(color: AppColors.textSecondary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgBase,
        hintStyle: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.ai, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        errorStyle: GoogleFonts.inter(color: AppColors.error, fontSize: 12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.textPrimary,
          foregroundColor: AppColors.bgDeep,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          side: const BorderSide(color: AppColors.border),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.bgBase,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.borderSubtle, thickness: 0.5),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: AppColors.textSecondary),
      ),
    );
  }
}
