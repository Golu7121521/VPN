import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFF0B0A10);
  static const surface = Color(0xFF16141F);
  static const surfaceVariant = Color(0xFF211E2E);
  static const primary = Color(0xFF8B5CF6);
  static const secondary = Color(0xFFD946EF);
  static const textSecondary = Color(0xFF9A98A8);
  static const divider = Color(0xFF262336);
  static const gradient = LinearGradient(
    colors: [Color(0xFF6D28D9), Color(0xFFC026D3)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTheme {
  static ThemeData get dark {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
      ),
      textTheme: base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF100E17),
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontSize: 12,
              color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textSecondary,
            )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textSecondary,
            )),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 4,
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.surfaceVariant,
        thumbColor: Colors.white,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
      ),
      dividerColor: AppColors.divider,
    );
  }
}
