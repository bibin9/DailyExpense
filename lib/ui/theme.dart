import 'package:flutter/material.dart';

/// Blue-and-white theme. Primary #1565C0 on white is 5.75:1 contrast (WCAG
/// AA for normal text); body text is near-black on white.
abstract final class AppColors {
  static const blue = Color(0xFF1565C0);
  static const blueDark = Color(0xFF0D47A1);
  static const blueLight = Color(0xFFE3F2FD);
  static const text = Color(0xFF1A1C1E);
  static const muted = Color(0xFF4A5560);
  static const danger = Color(0xFFB3261E);
}

ThemeData buildTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.blue,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.blue,
        onPrimary: Colors.white,
        surface: Colors.white,
        onSurface: AppColors.text,
        error: AppColors.danger,
      );
  const minTap = Size(64, 52);
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF6F8FB),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.blue,
      foregroundColor: Colors.white,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: minTap,
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: minTap),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: Color(0xFFDCE3EC)),
      ),
    ),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 10),
  );
}
