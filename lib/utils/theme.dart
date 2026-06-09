import 'package:flutter/material.dart';

class AppColors {
  static const brand     = Color(0xFFE8651A);
  static const teal      = Color(0xFF1B6B7A);
  static const teal2     = Color(0xFF134F5C);
  static const tealSoft  = Color(0xFFE6F4F6);
  static const ink       = Color(0xFF1A1A2E);
  static const ink2      = Color(0xFF2D3748);
  static const muted     = Color(0xFF718096);
  static const line      = Color(0xFFE2E8F0);
  static const bg        = Color(0xFFF0F7F9);
  static const white     = Color(0xFFFFFFFF);
  static const green     = Color(0xFF2ECC71);
  static const greenSoft = Color(0xFFE8F8F0);
  static const yellow    = Color(0xFFF59E0B);
  static const red       = Color(0xFFE53E3E);
}

class AppTheme {
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.teal,
      primary: AppColors.teal,
      secondary: AppColors.brand,
      surface: AppColors.white,
    ),
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.teal,
      foregroundColor: AppColors.white,
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.teal,
        foregroundColor: AppColors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
    ),
  );
}
