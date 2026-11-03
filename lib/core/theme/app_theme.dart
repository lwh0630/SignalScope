import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import 'glass.dart';
import 'glass_tokens.dart';

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
    final g = GlassColors.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ).copyWith(
          surface: g.base,
          surfaceContainerLowest: const Color(0xFF05080F),
          surfaceContainerLow: const Color(0xFF0C1322),
          surfaceContainer: g.panel,
          surfaceContainerHigh: const Color(0xFF18233B),
          surfaceContainerHighest: const Color(0xFF1E2A46),
          primary: const Color(0xFF3DD6F0),
        );
    return _build(scheme, g);
  }

  static ThemeData light() {
    final g = GlassColors.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    ).copyWith(surface: g.base, surfaceContainer: g.panel);
    return _build(scheme, g);
  }

  static ThemeData _build(ColorScheme scheme, GlassColors g) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      // The ambient background is painted under the Navigator; every Scaffold is
      // transparent. `canvasColor` stays opaque so menus remain readable.
      canvasColor: g.panel,
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Rd.md + 2),
    );
    final label = base.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
    );
    return base.copyWith(
      extensions: [g],
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: base.textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _GlassPageTransitions(),
          TargetPlatform.iOS: _GlassPageTransitions(),
          TargetPlatform.windows: _GlassPageTransitions(),
          TargetPlatform.linux: _GlassPageTransitions(),
          TargetPlatform.macOS: _GlassPageTransitions(),
          TargetPlatform.fuchsia: _GlassPageTransitions(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
        // A transparent bar is otherwise judged dark and gets light status-bar
        // icons on the light theme.
        systemOverlayStyle: scheme.brightness == Brightness.dark
            ? _overlayLight
            : _overlayDark,
      ),
      cardTheme: CardThemeData(
        color: g.fill,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rd.lg),
          side: BorderSide(color: g.hairline),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: scheme.primary.withValues(
          alpha: g.isDark ? 0.26 : 0.18,
        ),
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: g.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rd.xl),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: g.panel,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Rd.xl)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: g.panel,
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface,
        ),
        actionTextColor: scheme.primary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rd.md + 2),
          side: BorderSide(
            color: g.edgeLight.withValues(alpha: g.edgeLight.a * 0.7),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: g.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rd.md + 2),
        ),
      ),
      dividerTheme: DividerThemeData(color: g.hairline, space: 1, thickness: 1),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 4),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: buttonShape,
          textStyle: label,
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: buttonShape,
          textStyle: label,
          minimumSize: const Size(0, 42),
          side: BorderSide(
            color: g.edgeLight.withValues(alpha: g.edgeLight.a * 0.8),
          ),
          backgroundColor: g.fill,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: buttonShape, textStyle: label),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rd.md),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: g.fillSubtle,
          selectedBackgroundColor: scheme.primary.withValues(
            alpha: g.isDark ? 0.28 : 0.2,
          ),
          selectedForegroundColor: scheme.onSurface,
          side: BorderSide(color: g.hairline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rd.md),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.transparent
              : g.edgeLight,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? scheme.primary : g.fillSubtle,
        ),
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurfaceVariant,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: g.fillSubtle,
        selectedColor: scheme.primary.withValues(alpha: g.isDark ? 0.28 : 0.2),
        side: BorderSide(color: g.hairline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rd.md),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: g.fillSubtle,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rd.md),
          borderSide: BorderSide(color: g.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rd.md),
          borderSide: BorderSide(color: g.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rd.md),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        inactiveTrackColor: g.track,
        activeTrackColor: scheme.primary,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: g.track,
        circularTrackColor: g.track,
      ),
    );
  }
}

/// Status-bar styles for the transparent app bar.
const _overlayLight = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
);
const _overlayDark = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
);

/// Page transition: a pure horizontal carousel. The new page slides in from the
/// right while the page below slides out to the left, so the two never overlap.
///
/// Never fade or `Opacity` a page here: that creates an offscreen layer, so every
/// `BackdropFilter` inside samples an empty backdrop (the glass looks flat while
/// the transition runs, then pops into place) and each frame costs a full-screen
/// copy. [GlassMotionTracker] also switches the blur off while the slide runs.
class _GlassPageTransitions extends PageTransitionsBuilder {
  const _GlassPageTransitions();

  static final _enter = Tween(
    begin: const Offset(1, 0),
    end: Offset.zero,
  ).chain(CurveTween(curve: Motion.curve));
  static final _exit = Tween(
    begin: Offset.zero,
    end: const Offset(-1, 0),
  ).chain(CurveTween(curve: Motion.curve));

  @override
  Duration get transitionDuration => Motion.slow;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    return GlassMotionTracker(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: SlideTransition(
        position: animation.drive(_enter),
        child: SlideTransition(
          position: secondaryAnimation.drive(_exit),
          child: RepaintBoundary(child: child),
        ),
      ),
    );
  }
}
