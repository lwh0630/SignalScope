import 'package:flutter/material.dart';

/// Colours used to express signal quality consistently across the app.
class SignalColors {
  SignalColors._();

  static const excellent = Color(0xFF2EE6A6);
  static const good = Color(0xFF8BE04E);
  static const fair = Color(0xFFFFC53D);
  static const poor = Color(0xFFFF8A3D);
  static const bad = Color(0xFFFF4D5E);
  static const none = Color(0xFF6B7A90);

  static const chartA = Color(0xFF29C5F6);
  static const chartB = Color(0xFFB388FF);
  static const chartC = Color(0xFFFFB74D);
  static const chartD = Color(0xFF69F0AE);
}

class AppTheme {
  AppTheme._();

  static const Color seed = Color(0xFF00B8D4);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(
      surface: const Color(0xFF0B1220),
      surfaceContainerLowest: const Color(0xFF080D18),
      surfaceContainerLow: const Color(0xFF0F1727),
      surfaceContainer: const Color(0xFF131C30),
      surfaceContainerHigh: const Color(0xFF18233B),
      surfaceContainerHighest: const Color(0xFF1E2A46),
    );
    return _build(scheme);
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );
    return _build(scheme);
  }

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
    );
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primary.withValues(alpha: 0.22),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.35),
        space: 1,
        thickness: 1,
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
