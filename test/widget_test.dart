import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application/app.dart';
import 'package:flutter_application/core/providers.dart';
import 'package:flutter_application/data/platform/unsupported_platform.dart';
import 'package:flutter_application/features/shell/application/navigation.dart';

Future<ProviderContainer> _openApp(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        signalPlatformProvider.overrideWithValue(UnsupportedPlatform('test')),
      ],
      child: const SignalScopeApp(),
    ),
  );
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(SignalScopeApp)));
}

void main() {
  testWidgets('shows five navigation tabs and switches pages', (tester) async {
    await _openApp(tester);

    // One icon per destination in the bottom bar (the first one is selected,
    // so it shows its filled icon).
    expect(find.byIcon(Icons.dashboard_rounded), findsOneWidget);
    expect(find.byIcon(Icons.cell_tower_outlined), findsOneWidget);
    expect(find.byIcon(Icons.wifi_outlined), findsOneWidget);
    expect(find.byIcon(Icons.satellite_alt_outlined), findsOneWidget);
    expect(find.byIcon(Icons.tune_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.tune_outlined));
    await tester.pumpAndSettle();
    // Nav label + page title.
    expect(find.text('Settings'), findsNWidgets(2));
    expect(find.byIcon(Icons.tune), findsOneWidget);
  });

  testWidgets('swiping the pages and tapping the bar stay in sync', (
    tester,
  ) async {
    final container = await _openApp(tester);
    int selected() => container.read(currentTabProvider).index;
    expect(selected(), 0);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
    await tester.pumpAndSettle();
    expect(selected(), 1);

    // A tap on a far tab animates there without reporting the pages in between.
    await tester.tap(find.byIcon(Icons.satellite_alt_outlined));
    await tester.pumpAndSettle();
    expect(selected(), 3);

    await tester.fling(find.byType(PageView), const Offset(400, 0), 1500);
    await tester.pumpAndSettle();
    expect(selected(), 2);

    // Both ends of the bar work too (the first / last pill sits inside the
    // rounded ends of the glass).
    await tester.tap(find.byIcon(Icons.tune_outlined));
    await tester.pumpAndSettle();
    expect(selected(), 4);
    await tester.tap(find.byIcon(Icons.dashboard_outlined));
    await tester.pumpAndSettle();
    expect(selected(), 0);
  });

  testWidgets('the bar never overlaps the page content', (tester) async {
    await _openApp(tester);
    final bar = tester.getRect(find.byIcon(Icons.dashboard_rounded));
    final pages = tester.getRect(find.byType(PageView));
    // The pages end above the bar instead of scrolling under it.
    expect(pages.bottom, lessThanOrEqualTo(bar.top));
  });
}
