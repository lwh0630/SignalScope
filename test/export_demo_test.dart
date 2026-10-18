import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_application/app.dart';
import 'package:flutter_application/core/demo_mode.dart';
import 'package:flutter_application/core/history.dart';
import 'package:flutter_application/core/providers.dart';
import 'package:flutter_application/data/models/signal_history_point.dart';
import 'package:flutter_application/data/platform/demo_platform.dart';
import 'package:flutter_application/data/platform/unsupported_platform.dart';
import 'package:flutter_application/features/export/export_service.dart';
import 'package:flutter_application/features/settings/domain/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('export formats', () {
    const points = [
      SignalHistoryPoint(
        timestampMs: 1000,
        series: 'wifi.rssi',
        value: -60,
        unit: 'dBm',
      ),
      SignalHistoryPoint(
        timestampMs: 2000,
        series: 'a,"b"',
        value: 1.5,
        unit: 'dB',
      ),
    ];

    test('CSV has a header, CRLF rows and escapes special characters', () {
      final csv = ExportFormats.toCsv(points);
      final lines = csv.split('\r\n');
      expect(lines[0], ExportFormats.csvHeader);
      expect(lines[1], '1000,1970-01-01T00:00:01.000Z,wifi.rssi,-60.0,dBm');
      expect(lines[2], '2000,1970-01-01T00:00:02.000Z,"a,""b""",1.5,dB');
      expect(lines.last, isEmpty);
    });

    test('JSON carries metadata, source label and all samples', () {
      final text = ExportFormats.toJson(
        points: points,
        latest: const {'wifiConnection': null},
        platform: 'android',
        demo: false,
        historySeconds: 300,
        exportedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      );
      final doc = jsonDecode(text) as Map<String, Object?>;
      expect(doc['app'], 'SignalScope');
      expect(doc['dataSource'], 'device');
      expect(doc['exportedAtUtc'], '2026-01-02T03:04:05.000Z');
      expect(doc['sampleCount'], 2);
      expect(
        (doc['samples']! as List).first,
        containsPair('series', 'wifi.rssi'),
      );
      expect((doc['latest']! as Map).containsKey('wifiConnection'), isTrue);
    });

    test('demo exports are labelled in the JSON and in the file name', () {
      final text = ExportFormats.toJson(
        points: points,
        latest: const {},
        platform: 'demo',
        demo: true,
        historySeconds: 60,
        exportedAt: DateTime.utc(2026),
      );
      expect((jsonDecode(text) as Map)['dataSource'], contains('demo'));
      final now = DateTime(2026, 3, 4, 5, 6, 7);
      expect(
        ExportFormats.fileName(ExportFormat.csv, now),
        'signalscope_20260304_050607.csv',
      );
      expect(
        ExportFormats.fileName(ExportFormat.json, now, demo: true),
        'signalscope_demo_20260304_050607.json',
      );
    });
  });

  group('ExportActions', () {
    ProviderContainer makeContainer(FakeAndroidPlatform p) {
      final c = ProviderContainer(
        overrides: [
          signalPlatformProvider.overrideWithValue(p),
          initialSettingsProvider.overrideWithValue(const AppSettings()),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('nothing to export when history is empty', () async {
      final p = FakeAndroidPlatform();
      final c = makeContainer(p);
      final r = await c.read(exportActionsProvider).export(ExportFormat.csv);
      expect(r.status, ExportStatus.empty);
      expect(p.exported, isNull);
    });

    test('exports recorded samples via the platform', () async {
      final p = FakeAndroidPlatform();
      final c = makeContainer(p);
      c
          .read(historyProvider.notifier)
          .add('wifi.rssi', -61, 'dBm', timestampMs: 5000);
      final r = await c.read(exportActionsProvider).export(ExportFormat.csv);
      expect(r.status, ExportStatus.saved);
      expect(r.location, contains('signalscope_'));
      expect(p.exported, contains('wifi.rssi'));
    });
  });

  group('DemoData', () {
    test('is deterministic apart from timestamps (no randomness)', () {
      for (final tick in [0, 7, 123]) {
        final a = DemoData.cellular(1, tick)!;
        final b = DemoData.cellular(1, tick)!;
        expect(a.primaryDbm, b.primaryDbm);
        expect(a.servingLte!.rsrp, b.servingLte!.rsrp);
        expect(
          DemoData.wifiConnection(tick).rssi,
          DemoData.wifiConnection(tick).rssi,
        );
        expect(
          DemoData.gnss(tick).satellites.map((s) => s.cn0DbHz),
          DemoData.gnss(tick).satellites.map((s) => s.cn0DbHz),
        );
      }
    });

    test('SIM1 is LTE with an NR leg (NSA) and SIM2 is NR standalone, independently', () {
      final s1 = DemoData.cellular(1, 3)!;
      final s2 = DemoData.cellular(2, 3)!;
      expect(s1.nrMode, 'NSA');
      expect(s1.servingLte, isNotNull);
      expect(s2.nrMode, 'SA');
      expect(s2.servingLte, isNull);
      expect(s1.primaryDbm, isNot(s2.primaryDbm));
      expect(DemoData.cellular(9, 0), isNull);
    });

    test('values stay inside physically sensible ranges', () {
      for (var t = 0; t < 200; t++) {
        final lte = DemoData.cellular(1, t)!.servingLte!;
        expect(lte.rsrp, inInclusiveRange(-140, -44));
        final w = DemoData.wifiConnection(t).rssi!;
        expect(w, inInclusiveRange(-100, -30));
        for (final s in DemoData.gnss(t).satellites) {
          expect(s.azimuthDeg, inInclusiveRange(0, 360));
          expect(s.elevationDeg, inInclusiveRange(0, 90));
        }
      }
    });
  });

  group('demo mode switch', () {
    testWidgets(
      'platform without collectors gets sample data only while demo is on',
      (tester) async {
        late ProviderContainer container;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              realPlatformProvider.overrideWithValue(
                UnsupportedPlatform('windows'),
              ),
              initialSettingsProvider.overrideWithValue(
                const AppSettings(languageCode: 'en'),
              ),
            ],
            child: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const SignalScopeApp();
              },
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Not supported on this platform'), findsOneWidget);
        expect(find.textContaining('DEMO MODE'), findsNothing);
        expect(container.read(demoModeProvider), isFalse);

        container.read(demoModeProvider.notifier).set(true);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.textContaining('DEMO MODE'), findsOneWidget);
        expect(find.text('Not supported on this platform'), findsNothing);
        expect(find.text('SIM1 · Demo Carrier A'), findsOneWidget);
        expect(find.text('SIM2 · Demo Carrier B'), findsOneWidget);

        container.read(demoModeProvider.notifier).set(false);
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.textContaining('DEMO MODE'), findsNothing);
        expect(find.text('Not supported on this platform'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      },
    );
  });
}
