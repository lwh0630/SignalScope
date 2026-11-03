import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application/core/history.dart';
import 'package:flutter_application/core/providers.dart';
import 'package:flutter_application/data/platform/unsupported_platform.dart';
import 'package:flutter_application/shared/widgets/trend_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('trend lines are drawn thin', (tester) async {
    final container = ProviderContainer(
      overrides: [
        signalPlatformProvider.overrideWithValue(UnsupportedPlatform('test')),
      ],
    );
    addTearDown(container.dispose);
    final history = container.read(historyProvider.notifier);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < 20; i++) {
      history.add('t.a', -90.0 + i % 5, 'dBm', timestampMs: now + i * 1000);
      history.add('t.b', -80.0 - i % 3, 'dBm', timestampMs: now + i * 1000);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TrendCard(
                title: 'Trend',
                series: [
                  TrendSeries(
                    key: 't.a',
                    label: 'A',
                    unit: 'dBm',
                    color: Colors.blue,
                  ),
                  TrendSeries(
                    key: 't.b',
                    label: 'B',
                    unit: 'dBm',
                    color: Colors.green,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData, hasLength(2));
    for (final line in chart.data.lineBarsData) {
      expect(line.barWidth, kTrendLineWidth);
      expect(line.barWidth, lessThanOrEqualTo(1.5));
    }
  });
}
