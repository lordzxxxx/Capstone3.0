import 'package:flutter/material.dart';

/// The mobile palette mirrors the established web design system.
/// Keep these values in one place so new mobile screens do not drift back to
/// the earlier dark-teal theme.
abstract final class AppDesign {
  static const navy = Color(0xFF0B1F3A);
  static const navySoft = Color(0xFF163B66);
  static const blue = Color(0xFF2F80ED);
  static const blueSoft = Color(0xFFE7F0FF);
  static const page = Color(0xFFF4F7FB);
  static const surface = Colors.white;
  static const border = Color(0xFFD9E5F2);
  static const ink = Color(0xFF0B1F3A);
  static const muted = Color(0xFF4B6075);
  static const subtle = Color(0xFF728396);
  static const success = Color(0xFF27AE60);
  static const warning = Color(0xFFF2A93B);
  static const danger = Color(0xFFD64545);

  static ThemeData theme() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: page,
      colorScheme: base.colorScheme.copyWith(
        primary: blue,
        onPrimary: Colors.white,
        secondary: navySoft,
        onSecondary: Colors.white,
        surface: surface,
        onSurface: ink,
        outline: border,
        outlineVariant: border,
        error: danger,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontFamily: 'Manrope',
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: _inputBorder(border),
        enabledBorder: _inputBorder(border),
        focusedBorder: _inputBorder(blue, width: 2),
        labelStyle: const TextStyle(color: muted, fontWeight: FontWeight.w600),
        hintStyle: const TextStyle(color: subtle),
        prefixIconColor: blue,
        suffixIconColor: subtle,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: navySoft,
          side: const BorderSide(color: border),
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: blue,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      textTheme: base.textTheme
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
          ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: blue,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: blue,
        unselectedItemColor: subtle,
        elevation: 8,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
