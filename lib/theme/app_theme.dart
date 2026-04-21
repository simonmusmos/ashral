import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Color tokens ──────────────────────────────────────────────────────────────

abstract final class AppColors {
  // Backgrounds
  static const bgDeep = Color(0xFF030305);
  static const bgBase = Color(0xFF0A0A0F);
  static const bgElevated = Color(0xFF121218);
  static const bgOverlay = Color(0xFF0F0F1A);

  // Borders
  static const border = Color(0xFF1A1A26);
  static const borderSubtle = Color(0xFF0F0F18);

  // Foreground
  static const textPrimary = Color(0xFFEEEEF2);
  static const textSecondary = Color(0xFF8B8B9E);
  static const textMuted = Color(0xFF4A4A60);

  // Status: running / active
  static const running = Color(0xFF4ADE80);
  static const runningBg = Color(0xFF0A1F12);
  static const runningBorder = Color(0x264ADE80); // 15% opacity

  // Status: success / completed
  static const success = Color(0xFF22C55E);
  static const successBg = Color(0xFF091A0F);
  static const successBorder = Color(0x1A22C55E);

  // Status: active/in-progress task (indigo, not red)
  static const active = Color(0xFF818CF8);
  static const activeBg = Color(0xFF0E0E1F);
  static const activeBorder = Color(0x1A818CF8);

  // Status: waiting
  static const waiting = Color(0xFFFBBF24);
  static const waitingBg = Color(0xFF1A1500);
  static const waitingBorder = Color(0x1AFBBF24);

  // Status: error / failed
  static const error = Color(0xFFF87171);
  static const errorBg = Color(0xFF1A0A0A);
  static const errorBorder = Color(0x1AF87171);

  // Status: pending (dimmed)
  static const pending = Color(0xFF4A4A60);
  static const pendingBg = Color(0xFF0D0D14);

  // Accent: AI / Claude brand
  static const ai = Color(0xFFFB923C);
  static const aiBg = Color(0xFF1A0F06);

  // Terminal text
  static const terminalText = Color(0xFFA3E635); // lime-400
  static const terminalCmd = Color(0xFF7DD3FC);  // sky-300
  static const terminalWarn = Color(0xFFFBBF24);
  static const terminalErr = Color(0xFFF87171);
  static const terminalSuccess = Color(0xFF4ADE80);

  // Diff colors
  static const diffAdd = Color(0xFF4ADE80);
  static const diffRemove = Color(0xFFF87171);
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
        letterSpacing: letterSpacing ?? -0.3,
      );

  /// Plus Jakarta Sans — all UI text
  static TextStyle ui({
    double size = 15,
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.textPrimary,
    double? letterSpacing,
    double? height,
  }) =>
      GoogleFonts.plusJakartaSans(
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
    final jakartaBase =
        GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme);

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
      textTheme: jakartaBase.copyWith(
        bodyMedium:
            jakartaBase.bodyMedium?.copyWith(color: AppColors.textSecondary),
        bodySmall:
            jakartaBase.bodySmall?.copyWith(color: AppColors.textSecondary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgBase,
        hintStyle: GoogleFonts.plusJakartaSans(
            color: AppColors.textMuted, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.textPrimary),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        errorStyle:
            GoogleFonts.plusJakartaSans(color: AppColors.error, fontSize: 12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.textPrimary,
          foregroundColor: AppColors.bgDeep,
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.plusJakartaSans(
              fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          side: const BorderSide(color: AppColors.border),
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.plusJakartaSans(
              fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.bgBase,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dividerTheme:
          const DividerThemeData(color: AppColors.borderSubtle, thickness: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bgDeep,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          color: AppColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: AppColors.textSecondary),
      ),
    );
  }
}
