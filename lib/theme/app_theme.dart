import 'package:flutter/material.dart';

/// Centralized theme: colors, typography, light/dark.
/// Use Theme.of(context).colorScheme and context.textTheme in UI.
class AppTheme {
  AppTheme._();

  // Brand
  static const String appName = 'Jira Management';
  static const String appVersion = '1.0.0';

  // Colors (Jira-aligned)
  static const Color primary = Color(0xFF0052CC);
  static const Color primaryLight = Color(0xFF2684FF);
  static const Color surfaceLight = Color(0xFFF5F5F5);
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF172B4D);
  static const Color textSecondary = Color(0xFF5E6C84);
  static const Color textMuted = Color(0xFF6B778C);
  static const Color border = Color(0xFFDFE1E6);
  static const Color borderLight = Color(0xFFF0F0F0);
  static const Color error = Color(0xFFDE350B);
  static const Color errorBg = Color(0xFFFFE5E5);
  static const Color success = Color(0xFF00875A);
  static const Color successBg = Color(0xFFE3FCEF);

  // Surfaces & UI
  static const Color surfaceMuted = Color(0xFFF4F5F7);
  static const Color hint = Color(0xFF9FA6B2);
  static const Color primaryBg = Color(0xFFE3F2FD);

  // Status category colors
  static const Color statusDone = Color(0xFF00875A);
  static const Color statusInProgress = Color(0xFF0052CC);
  static const Color statusTodo = Color(0xFF6554C0);
  static const Color statusDefault = Color(0xFF999999);

  // Spacing scale (4, 8, 12, 16, 24, 32)
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 24;
  static const double spaceXxl = 32;

  // Font sizes
  static const double fontSizeXs = 11;
  static const double fontSizeSm = 12;
  static const double fontSizeMd = 13;
  static const double fontSizeBase = 14;
  static const double fontSizeLg = 16;
  static const double fontSizeXl = 18;
  static const double fontSizeXxl = 22;
  static const double fontSizeXxxl = 28;
  static const double fontSizeHuge = 48;

  // Icon sizes
  static const double iconSizeXs = 16;
  static const double iconSizeSm = 18;
  static const double iconSizeMd = 20;
  static const double iconSizeLg = 24;
  static const double iconSizeXl = 28;
  static const double iconSizeXxl = 48;
  static const double iconSizeHuge = 72;

  // Additional colors
  static const Color white = Colors.white;
  static const Color black = Colors.black;
  static const Color black54 = Colors.black54;
  static const Color black87 = Colors.black87;
  static const Color black26 = Colors.black26;
  static const Color black38 = Colors.black38;
  static const Color white70 = Colors.white70;
  
  // Overlay colors
  static const Color overlayDark = Color(0xFF172B4D);
  static const Color overlayLight = Color(0xFF5E6C84);
  static const Color overlayMuted = Color(0xFF7A869A);
  static const Color dividerColor = Color(0xFFDFE1E6);

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      primary: primary,
      surface: surfaceLight,
      error: error,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surfaceLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      textTheme: _textTheme(Brightness.light),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: surfaceCard,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceCard,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: primary,
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
    );
  }

  static ThemeData get dark {
    const primaryDark = Color(0xFF4C9AFF);
    const surfaceDark = Color(0xFF1E2128);
    const surfaceCardDark = Color(0xFF252A33);
    const textPrimaryDark = Color(0xFFE6EDFA);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryDark,
      brightness: Brightness.dark,
      primary: primaryDark,
      surface: surfaceDark,
      error: const Color(0xFFE34935),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surfaceDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceDark,
        foregroundColor: textPrimaryDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimaryDark,
        ),
      ),
      textTheme: _textTheme(Brightness.dark),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: surfaceCardDark,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceCardDark,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF3D4149)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryDark, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryDark,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryDark,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceCardDark,
        contentTextStyle: const TextStyle(color: textPrimaryDark),
      ),
    );
  }

  static TextTheme _textTheme(Brightness brightness) {
    final base = brightness == Brightness.light ? textPrimary : const Color(0xFFE6EDFA);
    final secondary = brightness == Brightness.light ? textSecondary : const Color(0xFFB6C2CF);
    return TextTheme(
      headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: base),
      headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: base),
      titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: base),
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: base),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: base),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: base),
      bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: secondary),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: base),
    );
  }
}
