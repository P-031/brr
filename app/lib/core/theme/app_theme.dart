import 'package:flutter/material.dart';

/// Sugarcane-field palette — sky blue, cane green, straw gold, white.
class AppColors {
  static const Color green = Color(0xFF2E7D32); // cane leaf
  static const Color greenLight = Color(0xFF66BB6A);
  static const Color gold = Color(0xFFC9A227); // dry straw
  static const Color goldLight = Color(0xFFF5E6B8);
  static const Color sky = Color(0xFF2D7FBF); // field sky
  static const Color skyLight = Color(0xFF9FC8EC);
  static const Color navy = Color(0xFF14213D);
  static const Color white = Colors.white;
}

class AppTheme {
  static ThemeData get theme {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.green,
      primary: AppColors.green,
      secondary: AppColors.sky,
      surface: Colors.white,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.green,
        foregroundColor: Colors.white,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.green,
          side: const BorderSide(color: AppColors.green),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
