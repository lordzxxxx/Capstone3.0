import 'package:flutter/material.dart';

/// Source of truth for the mobile healthcare visual system.
///
/// Legacy aliases such as [navySoft], [page], and [ink] are intentionally kept
/// so active feature screens can migrate without changing application logic.
abstract final class AppDesign {
  // Brand.
  static const blue = Color(0xFF2F80ED);
  static const bluePressed = Color(0xFF256FD1);
  static const navy = Color(0xFF173F70);
  static const blueSoft = Color(0xFFEAF3FF);
  static const teal = Color(0xFF159BAD);
  static const green = Color(0xFF219B68);
  static const orange = Color(0xFFFFA33B);
  static const red = Color(0xFFFF5151);
  static const pink = Color(0xFFF63373);
  static const skyBlue = Color(0xFF3BB7EA);

  // Surfaces and typography.
  static const page = Color(0xFFF5F7FA);
  static const canvas = Color(0xFFF8FAFC);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF14212B);
  static const muted = Color(0xFF52677D);
  static const subtle = Color(0xFF7C8C9C);
  static const disabled = Color(0xFFA8B3BF);
  static const border = Color(0xFFE2E8F0);
  static const borderStrong = Color(0xFFCBD5E1);
  static const chartGrid = Color(0xFFDCE6F2);

  // Semantic foreground/background pairs.
  static const success = Color(0xFF219B68);
  static const successBackground = Color(0xFFE8F7F0);
  static const warning = Color(0xFFF59E0B);
  static const warningBackground = Color(0xFFFFF7E6);
  static const danger = Color(0xFFEF4444);
  static const dangerBackground = Color(0xFFFEECEC);
  static const information = blue;
  static const informationBackground = blueSoft;
  static const neutral = Color(0xFF64748B);
  static const neutralBackground = Color(0xFFF1F5F9);

  // Compatibility alias used by existing screens.
  static const navySoft = navy;

  // Stable domain identities.
  static const patientRecords = blue;
  static const checkUp = navy;
  static const prenatal = pink;
  static const immunization = green;
  static const morbidity = orange;
  static const mortality = red;
  static const referrals = teal;
  static const communicable = skyBlue;
  static const nonCommunicable = teal;

  static const chartPalette = <Color>[
    blue,
    navy,
    teal,
    green,
    orange,
    pink,
    red,
    skyBlue,
  ];

  /// Maps healthcare wording by meaning. Specific high-risk phrases are
  /// evaluated first so e.g. "Completed with adverse event" stays dangerous.
  static StatusColors statusColors(String status) {
    final value = status.trim().toLowerCase().replaceAll(RegExp(r'[_-]+'), ' ');
    const dangerTerms = <String>[
      'completed with adverse event',
      'non adherent',
      'high risk',
      'uncontrolled',
      'deceased',
      'critical',
      'severe',
      'death',
      'missed',
      'overdue',
      'returned for correction',
      'adverse',
    ];
    const warningTerms = <String>[
      'under treatment',
      'moderate risk',
      'recovering',
      'monitoring',
      'partial',
      'pending',
      'active',
      'urgent',
      'scheduled',
      'pending certification',
      'follow up due',
      'due soon',
      'due',
    ];
    const successTerms = <String>[
      'fully immunized',
      'well managed',
      'low risk',
      'controlled',
      'completed',
      'recovered',
      'verified',
      'approved',
      'adherent',
      'certified',
      'resolved',
      'stable',
    ];
    if (dangerTerms.any(value.contains)) {
      return const StatusColors(danger, dangerBackground);
    }
    if (warningTerms.any(value.contains)) {
      return const StatusColors(warning, warningBackground);
    }
    if (successTerms.any(value.contains)) {
      return const StatusColors(success, successBackground);
    }
    if (value.contains('refer') ||
        value.contains('consult') ||
        value.contains('recorded') ||
        value.contains('in progress')) {
      return const StatusColors(information, informationBackground);
    }
    return const StatusColors(neutral, neutralBackground);
  }

  static ThemeData theme() {
    final base = ThemeData.light(useMaterial3: true);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: blue,
          brightness: Brightness.light,
          primary: blue,
          surface: surface,
          error: danger,
        ).copyWith(
          primary: blue,
          onPrimary: surface,
          primaryContainer: blueSoft,
          onPrimaryContainer: navy,
          secondary: teal,
          onSecondary: surface,
          secondaryContainer: informationBackground,
          onSecondaryContainer: navy,
          surface: surface,
          onSurface: ink,
          onSurfaceVariant: muted,
          outline: borderStrong,
          outlineVariant: border,
          error: danger,
          onError: surface,
          errorContainer: dangerBackground,
          onErrorContainer: danger,
          shadow: navy,
          scrim: navy,
        );

    final textTheme = base.textTheme
        .apply(fontFamily: 'Manrope', bodyColor: ink, displayColor: ink)
        .copyWith(
          headlineLarge: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
          headlineMedium: const TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
          headlineSmall: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
          titleLarge: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
          titleMedium: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
          bodyLarge: const TextStyle(fontSize: 15, color: muted),
          bodyMedium: const TextStyle(fontSize: 14, color: muted),
          bodySmall: const TextStyle(fontSize: 12, color: subtle),
          labelLarge: const TextStyle(fontWeight: FontWeight.w700),
        );

    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    return base.copyWith(
      brightness: Brightness.light,
      scaffoldBackgroundColor: page,
      canvasColor: canvas,
      colorScheme: scheme,
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: ink,
          fontFamily: 'Manrope',
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
        iconTheme: IconThemeData(color: ink),
        actionsIconTheme: IconThemeData(color: ink),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shadowColor: navy.withValues(alpha: .08),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: _inputBorder(borderStrong),
        enabledBorder: _inputBorder(borderStrong),
        focusedBorder: _inputBorder(blue, width: 2),
        errorBorder: _inputBorder(danger),
        focusedErrorBorder: _inputBorder(danger, width: 2),
        labelStyle: const TextStyle(color: muted, fontWeight: FontWeight.w600),
        floatingLabelStyle: const TextStyle(
          color: blue,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: const TextStyle(color: subtle),
        errorStyle: const TextStyle(color: danger),
        prefixIconColor: muted,
        suffixIconColor: subtle,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _primaryButtonStyle(rounded),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _primaryButtonStyle(rounded),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: navy,
          backgroundColor: surface,
          disabledForegroundColor: disabled,
          side: const BorderSide(color: borderStrong),
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          shape: rounded,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: blue,
          disabledForegroundColor: disabled,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: blue,
        foregroundColor: surface,
        elevation: 2,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: ink,
          fontFamily: 'Manrope',
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: TextStyle(
          color: muted,
          fontFamily: 'Manrope',
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
          side: BorderSide(color: border),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
        modalBarrierColor: Color(0x66173F70),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: blue,
        unselectedItemColor: subtle,
        elevation: 8,
        type: BottomNavigationBarType.fixed,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: blueSoft,
        elevation: 1,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w700),
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      dataTableTheme: const DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(canvas),
        dataRowColor: WidgetStatePropertyAll(surface),
        headingTextStyle: TextStyle(color: navy, fontWeight: FontWeight.w800),
        dataTextStyle: TextStyle(color: ink),
        dividerThickness: 1,
        decoration: BoxDecoration(
          color: surface,
          border: Border.fromBorderSide(BorderSide(color: border)),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        textStyle: TextStyle(color: ink),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(surface),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: neutralBackground,
        selectedColor: blueSoft,
        disabledColor: neutralBackground,
        side: const BorderSide(color: border),
        labelStyle: const TextStyle(
          color: neutral,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: const TextStyle(
          color: navy,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: navy,
        contentTextStyle: TextStyle(color: surface, fontFamily: 'Manrope'),
        actionTextColor: surface,
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: blue,
        linearTrackColor: blueSoft,
        circularTrackColor: blueSoft,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? blue : surface,
        ),
        checkColor: const WidgetStatePropertyAll(surface),
        side: const BorderSide(color: borderStrong, width: 1.5),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? blue : subtle,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? surface : subtle,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? blue : border,
        ),
      ),
      tooltipTheme: const TooltipThemeData(
        decoration: BoxDecoration(
          color: navy,
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        textStyle: TextStyle(color: surface),
      ),
    );
  }

  static ButtonStyle _primaryButtonStyle(OutlinedBorder shape) {
    return ButtonStyle(
      foregroundColor: const WidgetStatePropertyAll(surface),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return disabled;
        if (states.contains(WidgetState.pressed)) return bluePressed;
        return blue;
      }),
      elevation: const WidgetStatePropertyAll(0),
      minimumSize: const WidgetStatePropertyAll(Size(48, 44)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      ),
      shape: WidgetStatePropertyAll(shape),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: color, width: width),
      );
}

@immutable
class StatusColors {
  const StatusColors(this.foreground, this.background);

  final Color foreground;
  final Color background;
}
