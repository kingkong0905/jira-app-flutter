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
  
  // Additional UI colors
  static const Color borderAlt = Color(0xFFE1E4E8); // Alternative border color
  static const Color textMutedAlt = Color(0xFF8993A4); // Alternative muted text
  static const Color textMutedSecondary = Color(0xFF7A869A); // Secondary muted text
  static const Color textComment = Color(0xFF42526E); // Comment text color
  static const Color surfaceLightBlue = Color(0xFFE6FCFF); // Light blue background
  static const Color borderLightBlue = Color(0xFFB3D4FF); // Light blue border
  static const Color surfaceVeryLight = Color(0xFFEBECF0); // Very light background
  static const Color deleteAction = Color(0xFFFF5630); // Delete/destructive action color

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

  // Padding constants
  static const EdgeInsets paddingZero = EdgeInsets.zero;
  static EdgeInsets paddingAll(double value) => EdgeInsets.all(value);
  static EdgeInsets paddingSymmetric({double? horizontal, double? vertical}) => EdgeInsets.symmetric(horizontal: horizontal ?? 0, vertical: vertical ?? 0);
  static EdgeInsets paddingOnly({double? top, double? bottom, double? left, double? right}) => EdgeInsets.only(top: top ?? 0, bottom: bottom ?? 0, left: left ?? 0, right: right ?? 0);
  static EdgeInsets paddingFromLTRB(double left, double top, double right, double bottom) => EdgeInsets.fromLTRB(left, top, right, bottom);
  
  // Common padding values
  static const EdgeInsets paddingXs = EdgeInsets.all(spaceXs); // 4
  static const EdgeInsets paddingSm = EdgeInsets.all(spaceSm); // 8
  static const EdgeInsets paddingMd = EdgeInsets.all(spaceMd); // 12
  static const EdgeInsets paddingLg = EdgeInsets.all(spaceLg); // 16
  static const EdgeInsets paddingXl = EdgeInsets.all(spaceXl); // 24
  static const EdgeInsets paddingXxl = EdgeInsets.all(spaceXxl); // 32
  
  // Specific padding combinations
  static const EdgeInsets paddingHorizontalSm = EdgeInsets.symmetric(horizontal: spaceSm); // 8
  static const EdgeInsets paddingHorizontalMd = EdgeInsets.symmetric(horizontal: spaceMd); // 12
  static const EdgeInsets paddingHorizontalLg = EdgeInsets.symmetric(horizontal: spaceLg); // 16
  static const EdgeInsets paddingHorizontalXl = EdgeInsets.symmetric(horizontal: spaceXl); // 24
  
  static const EdgeInsets paddingVerticalSm = EdgeInsets.symmetric(vertical: spaceSm); // 8
  static const EdgeInsets paddingVerticalMd = EdgeInsets.symmetric(vertical: spaceMd); // 12
  static const EdgeInsets paddingVerticalLg = EdgeInsets.symmetric(vertical: spaceLg); // 16
  static const EdgeInsets paddingVerticalXl = EdgeInsets.symmetric(vertical: spaceXl); // 24
  
  static const EdgeInsets paddingHorizontalSmVerticalSm = EdgeInsets.symmetric(horizontal: spaceSm, vertical: spaceSm); // 8x8
  static const EdgeInsets paddingHorizontalMdVerticalMd = EdgeInsets.symmetric(horizontal: spaceMd, vertical: spaceMd); // 12x12
  static const EdgeInsets paddingHorizontalLgVerticalLg = EdgeInsets.symmetric(horizontal: spaceLg, vertical: spaceLg); // 16x16
  static const EdgeInsets paddingHorizontalXlVerticalMd = EdgeInsets.symmetric(horizontal: spaceXl, vertical: spaceMd); // 24x12
  
  // Additional padding values
  static const EdgeInsets padding5 = EdgeInsets.all(5);
  static const EdgeInsets padding6 = EdgeInsets.all(6);
  static const EdgeInsets padding10 = EdgeInsets.all(10);
  static const EdgeInsets padding14 = EdgeInsets.all(14);
  static const EdgeInsets padding18 = EdgeInsets.all(18);
  static const EdgeInsets padding20 = EdgeInsets.all(20);
  static const EdgeInsets padding28 = EdgeInsets.all(28);
  
  static const EdgeInsets paddingHorizontal10 = EdgeInsets.symmetric(horizontal: 10);
  static const EdgeInsets paddingHorizontal14 = EdgeInsets.symmetric(horizontal: 14);
  static const EdgeInsets paddingHorizontal20 = EdgeInsets.symmetric(horizontal: 20);
  static const EdgeInsets paddingHorizontal24 = EdgeInsets.symmetric(horizontal: 24);
  
  static const EdgeInsets paddingVertical6 = EdgeInsets.symmetric(vertical: 6);
  static const EdgeInsets paddingVertical10 = EdgeInsets.symmetric(vertical: 10);
  static const EdgeInsets paddingVertical14 = EdgeInsets.symmetric(vertical: 14);
  static const EdgeInsets paddingVertical18 = EdgeInsets.symmetric(vertical: 18);
  
  static const EdgeInsets paddingHorizontal10Vertical4 = EdgeInsets.symmetric(horizontal: 10, vertical: 4);
  static const EdgeInsets paddingHorizontal12Vertical5 = EdgeInsets.symmetric(horizontal: 12, vertical: 5);
  static const EdgeInsets paddingHorizontal12Vertical6 = EdgeInsets.symmetric(horizontal: 12, vertical: 6);
  static const EdgeInsets paddingHorizontal12Vertical12 = EdgeInsets.symmetric(horizontal: 12, vertical: 12);
  static const EdgeInsets paddingHorizontal14Vertical6 = EdgeInsets.symmetric(horizontal: 14, vertical: 6);
  static const EdgeInsets paddingHorizontal16Vertical12 = EdgeInsets.symmetric(horizontal: 16, vertical: 12);
  static const EdgeInsets paddingHorizontal20Vertical12 = EdgeInsets.symmetric(horizontal: 20, vertical: 12);
  static const EdgeInsets paddingHorizontal20Vertical14 = EdgeInsets.symmetric(horizontal: 20, vertical: 14);
  static const EdgeInsets paddingHorizontal24Vertical12 = EdgeInsets.symmetric(horizontal: 24, vertical: 12);
  
  static const EdgeInsets paddingTop8 = EdgeInsets.only(top: 8);
  static const EdgeInsets paddingBottom10 = EdgeInsets.only(bottom: 10);
  static const EdgeInsets paddingBottom14 = EdgeInsets.only(bottom: 14);
  static const EdgeInsets paddingBottom24 = EdgeInsets.only(bottom: 24);
  
  static EdgeInsets paddingFromLTRB16_16_16_0 = EdgeInsets.fromLTRB(16, 16, 16, 0);
  static EdgeInsets paddingFromLTRB16_0_16_12 = EdgeInsets.fromLTRB(16, 0, 16, 12);
  static EdgeInsets paddingFromLTRB16_0_16_0 = EdgeInsets.fromLTRB(16, 0, 16, 0);
  
  static const EdgeInsets paddingTop4 = EdgeInsets.only(top: 4);
  static const EdgeInsets paddingBottom8 = EdgeInsets.only(bottom: 8);
  static const EdgeInsets paddingBottom4 = EdgeInsets.only(bottom: 4);
  static const EdgeInsets paddingBottom12 = EdgeInsets.only(bottom: 12);
  static const EdgeInsets paddingRight4 = EdgeInsets.only(right: 4);
  static const EdgeInsets paddingRight8 = EdgeInsets.only(right: 8);
  static const EdgeInsets paddingRight12 = EdgeInsets.only(right: 12);
  static const EdgeInsets paddingLeft20 = EdgeInsets.only(left: 20);
  static const EdgeInsets paddingTop16 = EdgeInsets.only(top: 16);
  
  // Combined padding (top/bottom/right/left combinations)
  static const EdgeInsets paddingRight8Bottom4 = EdgeInsets.only(right: 8, bottom: 4);
  static const EdgeInsets paddingTop8Bottom4 = EdgeInsets.only(top: 8, bottom: 4);
  static const EdgeInsets paddingTop8Bottom8 = EdgeInsets.only(top: 8, bottom: 8);
  static const EdgeInsets paddingRight8Bottom8 = EdgeInsets.only(right: 8, bottom: 8);
  static const EdgeInsets paddingTop4Bottom4 = EdgeInsets.only(top: 4, bottom: 4);
  static const EdgeInsets paddingTop12Bottom8 = EdgeInsets.only(top: 12, bottom: 8);
  
  // EdgeInsets.fromLTRB combinations
  static EdgeInsets paddingFromLTRB16_12_16_8 = EdgeInsets.fromLTRB(16, 12, 16, 8);
  static EdgeInsets paddingFromLTRB20_16_20_20 = EdgeInsets.fromLTRB(20, 16, 20, 20);
  static EdgeInsets paddingFromLTRB20_16_20_16 = EdgeInsets.fromLTRB(20, 16, 20, 16);
  static EdgeInsets paddingFromLTRB12_10_8_10 = EdgeInsets.fromLTRB(12, 10, 8, 10);
  static EdgeInsets marginFromLTRB20_16_20_8 = EdgeInsets.fromLTRB(20, 16, 20, 8);
  
  static const EdgeInsets paddingHorizontal12Vertical10 = EdgeInsets.symmetric(horizontal: 12, vertical: 10);
  static const EdgeInsets paddingHorizontal16Vertical12 = EdgeInsets.symmetric(horizontal: 16, vertical: 12);
  static const EdgeInsets paddingVertical12 = EdgeInsets.symmetric(vertical: 12);
  
  static const double height4 = 4;
  static const double height18 = 18;
  static const double height44 = 44;
  static const double height64 = 64;
  static const double height200 = 200;

  // Height constants
  static const double heightXs = 1;
  static const double heightSm = 2;
  static const double heightMd = 6;
  static const double heightLg = 8;
  static const double heightXl = 10;
  static const double heightXxl = 12;
  static const double heightXxxl = 16;
  static const double heightXxxxl = 20;
  static const double heightXxxxxl = 24;
  static const double heightXxxxxxl = 28;
  static const double heightXxxxxxxl = 36;
  static const double heightXxxxxxxxl = 110;
  static const double heightXxxxxxxxxl = 120;

  // Width constants
  static const double widthXs = 2;
  static const double widthSm = 6;
  static const double widthMd = 8;
  static const double widthLg = 12;
  static const double widthXl = 20;
  static const double widthXxl = 24;
  static const double widthXxxl = 28;
  static const double widthXxxxl = 32;
  static const double widthXxxxxl = 36;
  static const double widthXxxxxxl = 110;
  static const double widthXxxxxxxl = 120;

  // Font sizes
  static const double fontSizeXxs = 10;
  static const double fontSizeXs = 11;
  static const double fontSizeSm = 12;
  static const double fontSizeMd = 13;
  static const double fontSizeBase = 14;
  static const double fontSizeBaseLg = 15;
  static const double fontSizeLg = 16;
  static const double fontSizeLgMd = 17;
  static const double fontSizeXl = 18;
  static const double fontSizeXlMd = 20;
  static const double fontSizeXxl = 22;
  static const double fontSizeXxlLg = 24;
  static const double fontSizeXxxl = 28;
  static const double fontSizeXxxlMd = 32;
  static const double fontSizeXxxlLg = 40;
  static const double fontSizeXxxlXl = 26;
  static const double fontSizeXxxlXxl = 36;
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
          borderSide: const BorderSide(color: primary, width: AppTheme.widthXs),
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
