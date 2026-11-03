import 'package:flutter/material.dart';
import 'package:flutter_application/app.dart';
import 'package:flutter_application/core/providers.dart';
import 'package:flutter_application/core/theme/app_theme.dart';
import 'package:flutter_application/core/theme/glass.dart';
import 'package:flutter_application/data/platform/unsupported_platform.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.dark(),
  home: Scaffold(body: child),
);

BackdropFilter _backdrop(WidgetTester tester) =>
    tester.widget<BackdropFilter>(find.byType(BackdropFilter));

void main() {
  group('GlassCard blur', () {
    testWidgets('does no backdrop blur by default', (tester) async {
      await tester.pumpWidget(_host(const GlassCard(child: Text('x'))));
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('blurs when the app asks for it (picture background)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const GlassCardBlur(blur: 14, child: GlassCard(child: Text('x'))),
        ),
      );
      expect(_backdrop(tester).enabled, isTrue);
    });

    testWidgets('an explicit blur wins over the app default', (tester) async {
      await tester.pumpWidget(
        _host(
          const GlassCardBlur(
            blur: 14,
            child: GlassCard(blur: 0, child: Text('x')),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('is switched off while the glass is moving', (tester) async {
      await tester.pumpWidget(
        _host(
          const GlassMotionScope(
            moving: true,
            child: GlassCardBlur(blur: 14, child: GlassCard(child: Text('x'))),
          ),
        ),
      );
      expect(_backdrop(tester).enabled, isFalse);
    });
  });

  group('GlassSurface', () {
    testWidgets('blurs by default and not with blur 0', (tester) async {
      await tester.pumpWidget(_host(const GlassSurface(child: Text('x'))));
      expect(_backdrop(tester).enabled, isTrue);

      await tester.pumpWidget(
        _host(const GlassSurface(blur: 0, child: Text('x'))),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('an outer moving scope reaches a nested tracker', (
      tester,
    ) async {
      final done = AnimationController(vsync: tester);
      addTearDown(done.dispose);
      await tester.pumpWidget(
        _host(
          GlassMotionScope(
            moving: true,
            child: GlassMotionTracker(
              animation: done,
              secondaryAnimation: done,
              child: const GlassSurface(child: Text('x')),
            ),
          ),
        ),
      );
      // The tracker's own animation is idle, but the outer scope still wins.
      expect(_backdrop(tester).enabled, isFalse);
    });
  });

  testWidgets('with the default glow only the bottom bar blurs', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          signalPlatformProvider.overrideWithValue(UnsupportedPlatform('test')),
        ],
        child: const SignalScopeApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(BackdropFilter), findsOneWidget);
  });
}
