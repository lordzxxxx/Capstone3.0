import 'package:flutter/material.dart';

/// Centralized color palette for the Smart Health Integration web app.
///
/// This formalizes the palette that was already independently redeclared as
/// local `_primaryAqua` / `_darkDeepTeal` / `_secondaryIceBlue` / etc.
/// constants across ~40+ files under `lib/web/` (e.g. `login.dart`,
/// `bho_login.dart`, `patient.dart`, `landing.dart`). [primary] (`0xFF00A8B5`)
/// is the teal that is actually in production use throughout the app; it
/// supersedes the paler `0xFF8ED7DA` that only the root `lib/main.dart`
/// `ThemeData` used.
///
/// New/updated screens should read colors from here instead of redeclaring
/// local constants. Existing screens are intentionally left untouched by
/// this change — see the panel revision notes for the migration plan.
class AppColors {
  AppColors._();

  // Brand
  /// Canonical brand teal. Matches the `_primaryAqua` constant already
  /// redeclared in the large majority of `lib/web/*` screens.
  static const Color primary = Color(0xFF2F80ED);

  /// Canonical secondary blue-teal. Matches the `_secondaryIceBlue` value
  /// used in login/signup/landing screens (18 files), not the lighter
  /// `0xFFC6D4E1` used only by the unused `lib/web/shell/main.dart`.
  static const Color secondary = Color(0xFF163B66);

  // Dark surfaces (used across dozens of dark-themed auth/portal screens)
  /// Deepest dark teal — page/backdrop background on dark screens.
  /// Matches `_darkDeepTeal` as declared in the majority of `lib/web/*`
  /// files (~30 occurrences).
  static const Color backgroundDark = Color(0xFF071A33);

  /// Slightly lighter dark teal — raised surfaces/panels/sidebars on top of
  /// [backgroundDark]. Matches `_sidebarDark` in `landing.dart` and
  /// `_darkDeepTeal` as declared in `lib/main.dart` itself (~29
  /// occurrences).
  static const Color surfaceDark = Color(0xFF0D274D);

  // Light surfaces
  /// Canonical light background. Matches `_lightOffWhite` (most common
  /// value across `lib/web/*`, 20+ occurrences).
  static const Color backgroundLight = Color(0xFFF4F7FB);
  static const Color surfaceLight = Colors.white;

  // Text
  static const Color textPrimary = Color(0xFF0B1F3A);
  static const Color textSecondary = Color(0xFF4B6075);
  static const Color textOnDark = Color(0xFFF8FBFF);

  // Status — formalized from the hex values already used consistently for
  // snackbars/validation across auth screens (forgot.dart, signup.dart,
  // reset_with_code.dart, main.dart's error color).
  static const Color success = Color(0xFF388E3C);
  static const Color warning = Color(0xFFF57C00);
  static const Color error = Color(0xFFD32F2F);
}

/// Shared spacing scale. Mirrors the paddings/gaps already predominant
/// across `lib/web/*` (4/8/16/24/32 covers the vast majority of the
/// `EdgeInsets`/`SizedBox` values already in use).
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

/// Builds the app's [ThemeData] from [AppColors]/[AppSpacing] so the visual
/// identity is defined in exactly one place.
class AppTheme {
  AppTheme._();

  /// Mont is the system typeface for all CHO/BHW web surfaces. The landing
  /// page deliberately overrides its local text styles to retain its
  /// marketing typography.
  static const String fontFamily = 'Mont';

  static ThemeData light({bool isWeb = false}) {
    final colorScheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.secondary,
      onSecondary: AppColors.textOnDark,
      surface: AppColors.backgroundLight,
      onSurface: AppColors.textPrimary,
      outline: AppColors.textSecondary,
      outlineVariant: AppColors.textSecondary,
      error: AppColors.error,
      onError: Colors.white,
    );

    const textTheme = TextTheme(
      // Hero / display — large marketing-style headings.
      displayLarge: TextStyle(
        fontSize: 40,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
      displayMedium: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
      displaySmall: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
      // Headline — hero support copy / large section headers.
      headlineLarge: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      headlineSmall: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      // Title — page titles (titleLarge) and section titles (titleMedium).
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      // Body — main content text, readable base size.
      // Mont ExtraLight is intentionally reserved for decorative/marketing
      // text. Normal application copy uses the readable supplied Mont face.
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
      // Labels — buttons and captions.
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.backgroundLight,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surfaceDark,
        foregroundColor: AppColors.textOnDark,
        elevation: 0,
        centerTitle: false,
        toolbarHeight: isWeb ? 72 : null,
        iconTheme: const IconThemeData(color: AppColors.textOnDark),
        titleTextStyle: TextStyle(
          color: AppColors.textOnDark,
          fontSize: isWeb ? 18 : 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceLight,
        elevation: 1,
        shadowColor: AppColors.secondary.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
          horizontal: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md,
            horizontal: AppSpacing.lg,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColors.textSecondary.withValues(alpha: 0.3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColors.textSecondary.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.textSecondary.withValues(alpha: 0.2),
        thickness: 1,
        space: 1,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.surfaceDark,
        scrimColor: Color(0x66071A33),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.secondary.withValues(alpha: 0.15),
        labelStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md - AppSpacing.xs,
          vertical: AppSpacing.sm,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceDark,
        contentTextStyle: const TextStyle(color: AppColors.textOnDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
