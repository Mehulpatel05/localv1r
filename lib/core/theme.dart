import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

@immutable
class NearhoodColors extends ThemeExtension<NearhoodColors> {
  final Color bg;
  final Color ink;
  final Color muted;
  final Color line;
  final Color field;
  final Color field2;
  final Color btn;
  final Color btnink;
  final Color page;
  final Color danger;
  final Color streets;

  const NearhoodColors({
    required this.bg,
    required this.ink,
    required this.muted,
    required this.line,
    required this.field,
    required this.field2,
    required this.btn,
    required this.btnink,
    required this.page,
    required this.danger,
    required this.streets,
  });

  static const NearhoodColors lightWhiteScheme = NearhoodColors(
    bg: AppColors.surface,
    ink: AppColors.textPrimary,
    muted: AppColors.textMuted,
    line: AppColors.divider,
    field: AppColors.surface,
    field2: AppColors.chipBg,
    btn: AppColors.primary,
    btnink: Colors.white,
    page: AppColors.background,
    danger: AppColors.error,
    streets: Color(0x1A3A0F34),
  );

  static const NearhoodColors light = lightWhiteScheme;
  static const NearhoodColors dark = lightWhiteScheme;

  @override
  NearhoodColors copyWith({
    Color? bg,
    Color? ink,
    Color? muted,
    Color? line,
    Color? field,
    Color? field2,
    Color? btn,
    Color? btnink,
    Color? page,
    Color? danger,
    Color? streets,
  }) {
    return NearhoodColors(
      bg: bg ?? this.bg,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      line: line ?? this.line,
      field: field ?? this.field,
      field2: field2 ?? this.field2,
      btn: btn ?? this.btn,
      btnink: btnink ?? this.btnink,
      page: page ?? this.page,
      danger: danger ?? this.danger,
      streets: streets ?? this.streets,
    );
  }

  @override
  NearhoodColors lerp(ThemeExtension<NearhoodColors>? other, double t) {
    if (other is! NearhoodColors) return this;
    return NearhoodColors(
      bg: Color.lerp(bg, other.bg, t) ?? bg,
      ink: Color.lerp(ink, other.ink, t) ?? ink,
      muted: Color.lerp(muted, other.muted, t) ?? muted,
      line: Color.lerp(line, other.line, t) ?? line,
      field: Color.lerp(field, other.field, t) ?? field,
      field2: Color.lerp(field2, other.field2, t) ?? field2,
      btn: Color.lerp(btn, other.btn, t) ?? btn,
      btnink: Color.lerp(btnink, other.btnink, t) ?? btnink,
      page: Color.lerp(page, other.page, t) ?? page,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
      streets: Color.lerp(streets, other.streets, t) ?? streets,
    );
  }
}

extension NearhoodThemeContext on BuildContext {
  NearhoodColors get nearhoodColors {
    final colors = Theme.of(this).extension<NearhoodColors>();
    return colors ?? NearhoodColors.lightWhiteScheme;
  }
}

class NearhoodTheme {
  const NearhoodTheme._();

  static ThemeData get customTheme {
    final baseTextTheme =
        GoogleFonts.plusJakartaSansTextTheme(ThemeData.light().textTheme);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      cardColor: AppColors.surface,
      dividerColor: AppColors.divider,
      dialogTheme: const DialogThemeData(backgroundColor: AppColors.surface),
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
      ),
      textTheme: baseTextTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      extensions: const <ThemeExtension<dynamic>>[
        NearhoodColors.lightWhiteScheme,
      ],
    );
  }

  static ThemeData get lightTheme => customTheme;
  static ThemeData get darkTheme => customTheme;
}
