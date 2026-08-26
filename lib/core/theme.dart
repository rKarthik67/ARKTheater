import 'package:flutter/material.dart';

/// ARKTheater's visual identity: dark, cinema-like, with a single accent
/// color so it reads consistently on phones, tablets, desktop windows, and
/// TV-sized displays alike. Palette matches the ARK Theatre logo's violet/
/// near-black lockup (see assets/images/splash_logo.png) rather than the
/// app's original red.
class AppTheme {
  AppTheme._();

  static const Color background = Color(0xFF0A0612);
  static const Color surface = Color(0xFF15101F);
  static const Color surfaceVariant = Color(0xFF211A38);
  static const Color accent = Color(0xFF8B5CF6);
  static const Color textPrimary = Color(0xFFF5F3FA);
  static const Color textSecondary = Color(0xFFAFA8C7);

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        secondary: accent,
        surface: surface,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textPrimary,
      ),
      cardColor: surface,
      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: surface,
        selectedIconTheme: IconThemeData(color: accent),
        selectedLabelTextStyle: TextStyle(color: accent),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: accent,
        unselectedItemColor: textSecondary,
      ),
    );
  }
}
