import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Exact design tokens from the Nearhood Black & White Design spec.
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

  /// Light Mode Tokens from CSS :root
  static const NearhoodColors light = NearhoodColors(
    bg: Color(0xFFFFFFFF),
    ink: Color(0xFF000000),
    muted: Color(0xFF6E6E6E),
    line: Color(0xFFE6E6E6),
    field: Color(0xFFF4F4F4),
    field2: Color(0xFFEAEAEA),
    btn: Color(0xFF000000),
    btnink: Color(0xFFFFFFFF),
    page: Color(0xFFEDEDED),
    danger: Color(0xFFC2402D),
    streets: Color(0x12000000), // rgba(0,0,0,0.07)
  );

  /// Dark Mode Tokens from CSS :root[data-theme="dark"]
  static const NearhoodColors dark = NearhoodColors(
    bg: Color(0xFF000000),
    ink: Color(0xFFFFFFFF),
    muted: Color(0xFF9A9A9A),
    line: Color(0xFF262626),
    field: Color(0xFF141414),
    field2: Color(0xFF1F1F1F),
    btn: Color(0xFFFFFFFF),
    btnink: Color(0xFF000000),
    page: Color(0xFF0A0A0A),
    danger: Color(0xFFC2402D),
    streets: Color(0x17FFFFFF), // rgba(255,255,255,0.09)
  );

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
    return colors ?? NearhoodColors.light;
  }
}

class NearhoodTheme {
  const NearhoodTheme._();

  static ThemeData get lightTheme {
    final baseTextTheme =
        GoogleFonts.plusJakartaSansTextTheme(ThemeData.light().textTheme);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: NearhoodColors.light.bg,
      colorScheme: ColorScheme.light(
        primary: NearhoodColors.light.btn,
        onPrimary: NearhoodColors.light.btnink,
        surface: NearhoodColors.light.bg,
        onSurface: NearhoodColors.light.ink,
        error: NearhoodColors.light.danger,
      ),
      textTheme: baseTextTheme.apply(
        bodyColor: NearhoodColors.light.ink,
        displayColor: NearhoodColors.light.ink,
      ),
      extensions: const <ThemeExtension<dynamic>>[
        NearhoodColors.light,
      ],
    );
  }

  static ThemeData get darkTheme {
    final baseTextTheme =
        GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: NearhoodColors.dark.bg,
      colorScheme: ColorScheme.dark(
        primary: NearhoodColors.dark.btn,
        onPrimary: NearhoodColors.dark.btnink,
        surface: NearhoodColors.dark.bg,
        onSurface: NearhoodColors.dark.ink,
        error: NearhoodColors.dark.danger,
      ),
      textTheme: baseTextTheme.apply(
        bodyColor: NearhoodColors.dark.ink,
        displayColor: NearhoodColors.dark.ink,
      ),
      extensions: const <ThemeExtension<dynamic>>[
        NearhoodColors.dark,
      ],
    );
  }
}
