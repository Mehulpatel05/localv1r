import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// App-wide theme extension adhering to the user's custom color scheme:
/// Background: Black (#000000)
/// Containers / Other: Deep Teal (#072E33)
/// Text: White (#FFFFFF)
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

  static const NearhoodColors darkTealScheme = NearhoodColors(
    bg: Color(0xFF000000), // Background Black
    ink: Color(0xFFFFFFFF), // Text White
    muted: Color(0xFF90B4B6), // Light Teal-Slate Muted Text
    line: Color(0xFF0C4148), // Border / Divider Teal
    field: Color(0xFF072E33), // Other / Container Deep Teal (#072E33)
    field2: Color(0xFF0E4B52), // Secondary Surface Deep Teal
    btn: Color(0xFF072E33), // Primary Button Deep Teal (#072E33)
    btnink: Color(0xFFFFFFFF), // Button Text White
    page: Color(0xFF000000), // Page Background Black
    danger: Color(0xFFEF4444),
    streets: Color(0x33072E33),
  );

  static const NearhoodColors light = darkTealScheme;
  static const NearhoodColors dark = darkTealScheme;

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
    return colors ?? NearhoodColors.darkTealScheme;
  }
}

class NearhoodTheme {
  const NearhoodTheme._();

  static ThemeData get customTheme {
    final baseTextTheme =
        GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF000000), // Background Black
      canvasColor: const Color(0xFF000000),
      cardColor: const Color(0xFF072E33), // Other Deep Teal
      dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF072E33)),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF072E33),
        onPrimary: Colors.white,
        surface: Color(0xFF072E33),
        onSurface: Colors.white,
        error: Color(0xFFEF4444),
      ),
      textTheme: baseTextTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF000000),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      extensions: const <ThemeExtension<dynamic>>[
        NearhoodColors.darkTealScheme,
      ],
    );
  }

  static ThemeData get lightTheme => customTheme;
  static ThemeData get darkTheme => customTheme;
}
