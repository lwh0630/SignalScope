import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application/app.dart';
import 'package:flutter_application/core/providers.dart';
import 'package:flutter_application/data/platform/unsupported_platform.dart';

void main() {
  testWidgets('shows five navigation tabs and switches pages', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          signalPlatformProvider.overrideWithValue(UnsupportedPlatform('test')),
        ],
        child: const SignalScopeApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(NavigationDestination), findsNWidgets(5));

    await tester.tap(find.byIcon(Icons.tune_outlined));
    await tester.pumpAndSettle();
    // Nav label + page title.
    expect(find.text('Settings'), findsNWidgets(2));
  });
}
