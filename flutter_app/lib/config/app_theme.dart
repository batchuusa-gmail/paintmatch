import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const background = Color(0xFF111111);
  static const card = Color(0xFF1a1a1a);
  static const bottomNav = Color(0xFF0d0d0d);
  static const accent = Color(0xFFc9a06a);
  static const accentDim = Color(0x33c9a06a);
  static const textPrimary = Color(0xFFffffff);
  static const textSecondary = Color(0xFF888888);
  static const border = Color(0x14ffffff); // rgba(255,255,255,0.08)
  static const error = Color(0xFFe05c5c);
  static const success = Color(0xFF5cb85c);
}

class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.accent,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        secondary: AppColors.accent,
        surface: AppColors.card,
        error: AppColors.error,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: GoogleFonts.playfairDisplayTextTheme().copyWith(
        displayLarge: GoogleFonts.playfairDisplay(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        displayMedium: GoogleFonts.playfairDisplay(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        headlineLarge: GoogleFonts.playfairDisplay(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        headlineMedium: GoogleFonts.playfairDisplay(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        headlineSmall: GoogleFonts.playfairDisplay(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        titleLarge: GoogleFonts.playfairDisplay(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        titleMedium: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500, fontSize: 16),
        titleSmall: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500, fontSize: 14),
        bodyLarge: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
        bodyMedium: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        bodySmall: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        labelLarge: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 15),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.bottomNav,
        indicatorColor: AppColors.accentDim,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.accent);
          }
          return const IconThemeData(color: AppColors.textSecondary);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w600);
          }
          return const TextStyle(color: AppColors.textSecondary, fontSize: 11);
        }),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          minimumSize: const Size.fromHeight(52),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          side: const BorderSide(color: AppColors.accent),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          minimumSize: const Size.fromHeight(52),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.accent),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.card,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
