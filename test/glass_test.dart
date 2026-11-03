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

    testWidgets('stays on while a page slides in (route push, page swipe)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const GlassCardBlur(
            blur: 14,
            child: Scaffold(body: GlassCard(child: Text('home'))),
          ),
        ),
      );
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const GlassCardBlur(
            blur: 14,
            child: Scaffold(body: GlassCard(child: Text('detail'))),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120)); // mid-transition
      final filters = tester.widgetList<BackdropFilter>(
        find.byType(BackdropFilter),
      );
      expect(filters, isNotEmpty);
      expect(filters.every((f) => f.enabled), isTrue);
      await tester.pumpAndSettle();
    });
  });

  group('card shadow', () {
    // Painters of the shadow layer: the only CustomPaint with a `painter`.
    int shadows(WidgetTester tester) => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((p) => p.painter != null)
        .length;

    testWidgets('is a single repaint-isolated layer under the card', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const GlassCard(child: Text('x'))));
      expect(shadows(tester), 1);
    });

    testWidgets('does not change the card size', (tester) async {
      await tester.pumpWidget(
        _host(
          const Center(
            child: GlassCard(child: SizedBox(width: 120, height: 40)),
          ),
        ),
      );
      expect(tester.getSize(find.byType(GlassCard)), const Size(120, 40));
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
