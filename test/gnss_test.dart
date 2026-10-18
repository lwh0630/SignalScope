import 'dart:math' as math;

import 'package:flutter_application/core/history.dart';
import 'package:flutter_application/core/lifecycle.dart';
import 'package:flutter_application/core/providers.dart';
import 'package:flutter_application/data/models/gnss_info.dart';
import 'package:flutter_application/features/gnss/application/gnss_controller.dart';
import 'package:flutter_application/features/gnss/data/gnss_repository.dart';
import 'package:flutter_application/features/gnss/presentation/cn0_bars.dart';
import 'package:flutter_application/features/gnss/presentation/sky_plot.dart';
import 'package:flutter_application/features/monitoring/monitor_status.dart';
import 'package:flutter_application/features/settings/domain/app_settings.dart';
import 'package:flutter_application/features/shell/application/navigation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GnssSnapshot model', () {
    test('parses native map; missing values stay null (never 0)', () {
      final s = GnssSnapshot.fromMap({
        'timestampMs': 20000,
        'gnssSupported': true,
        'providerEnabled': true,
        'engineStarted': true,
        'ttffMs': 8200,
        'location': {
          'latitude': 31.2304,
          'longitude': 121.4737,
          'horizontalAccuracyM': 4.5,
          'timeMs': 19000,
          'provider': 'gps',
        },
        'satellites': [
          {'svid': 5, 'constellation': 1, 'azimuthDeg': 120.0, 'elevationDeg': 45.0, 'cn0DbHz': 38.5, 'usedInFix': true},
          {'svid': 12, 'constellation': 5, 'azimuthDeg': 10.0, 'elevationDeg': 80.0, 'cn0DbHz': 0.0, 'usedInFix': false},
        ],
        'issues': <Object?>[],
      });
      expect(s.ttffMs, 8200);
      expect(s.location!.hasFix, isTrue);
      expect(s.location!.altitudeM, isNull);
      expect(s.location!.speedMps, isNull);
      expect(s.location!.isMock, isNull);
      expect(s.satellites.first.constellation, Constellation.gps);
      expect(s.satellites.last.constellation, Constellation.beidou);
      expect(s.satellites.first.carrierFrequencyHz, isNull);
      expect(s.visibleCount, 2);
      expect(s.usedCount, 1);
    });

    test('unknown constellation code maps to unknown', () {
      expect(Constellation.fromCode(99), Constellation.unknown);
      expect(Constellation.fromCode(null), Constellation.unknown);
    });
  });

  group('GnssRepository derived values', () {
    test('average C/N0 counts only tracked satellites', () {
      const sats = [
        SatelliteInfo(svid: 1, constellation: Constellation.gps, cn0DbHz: 40),
        SatelliteInfo(svid: 2, constellation: Constellation.gps, cn0DbHz: 30),
        SatelliteInfo(svid: 3, constellation: Constellation.gps, cn0DbHz: 0),
        SatelliteInfo(svid: 4, constellation: Constellation.gps),
      ];
      expect(GnssRepository.averageCn0(sats), 35);
      expect(GnssRepository.trackedCount(sats), 2);
    });

    test('average is null when nothing is tracked', () {
      const sats = [SatelliteInfo(svid: 3, constellation: Constellation.gps, cn0DbHz: 0)];
      expect(GnssRepository.averageCn0(sats), isNull);
      expect(GnssRepository.averageCn0(const []), isNull);
    });
  });

  group('sky plot geometry', () {
    test('zenith is the centre, horizon is the rim, north is up', () {
      final zenith = SkyPlotPainter.unitPosition(
          const SatelliteInfo(svid: 1, constellation: Constellation.gps, azimuthDeg: 123, elevationDeg: 90))!;
      expect(zenith.distance, closeTo(0, 1e-9));

      final north = SkyPlotPainter.unitPosition(
          const SatelliteInfo(svid: 1, constellation: Constellation.gps, azimuthDeg: 0, elevationDeg: 0))!;
      expect(north.dx, closeTo(0, 1e-9));
      expect(north.dy, closeTo(-1, 1e-9));

      final east = SkyPlotPainter.unitPosition(
          const SatelliteInfo(svid: 1, constellation: Constellation.gps, azimuthDeg: 90, elevationDeg: 0))!;
      expect(east.dx, closeTo(1, 1e-9));
      expect(east.dy, closeTo(0, 1e-9));

      final mid = SkyPlotPainter.unitPosition(
          const SatelliteInfo(svid: 1, constellation: Constellation.gps, azimuthDeg: 180, elevationDeg: 45))!;
      expect(mid.dx, closeTo(0, 1e-9));
      expect(mid.dy, closeTo(0.5, 1e-9));
      expect(math.sqrt(mid.dx * mid.dx + mid.dy * mid.dy), closeTo(0.5, 1e-9));
    });

    test('unknown azimuth or elevation is not plotted', () {
      expect(SkyPlotPainter.unitPosition(const SatelliteInfo(svid: 1, constellation: Constellation.gps)), isNull);
      expect(
        SkyPlotPainter.unitPosition(
            const SatelliteInfo(svid: 1, constellation: Constellation.gps, azimuthDeg: 10)),
        isNull,
      );
    });

    test('bars keep a stable order by constellation then SVID', () {
      final sorted = sortForDisplay(const [
        SatelliteInfo(svid: 9, constellation: Constellation.beidou),
        SatelliteInfo(svid: 20, constellation: Constellation.gps),
        SatelliteInfo(svid: 3, constellation: Constellation.gps),
      ]);
      expect(sorted.map((s) => '${s.constellation.code}-${s.svid}'), ['1-3', '1-20', '5-9']);
    });
  });

  group('GnssState.fixState', () {
    GnssState stateOf(GnssSnapshot s) => GnssState(snapshot: s);

    test('unknown before first snapshot', () {
      expect(const GnssState().fixState, FixState.unknown);
    });

    test('unsupported hardware', () {
      expect(stateOf(const GnssSnapshot(gnssSupported: false, issues: ['gnss_unsupported'])).fixState,
          FixState.unsupported);
    });

    test('blocked by permission / location switch', () {
      expect(stateOf(const GnssSnapshot(gnssSupported: true, issues: ['no_location_permission'])).fixState,
          FixState.blocked);
      expect(stateOf(const GnssSnapshot(gnssSupported: true, issues: ['location_off'])).fixState, FixState.blocked);
    });

    test('searching without location, fixed with fresh location, stale when old', () {
      expect(stateOf(const GnssSnapshot(gnssSupported: true)).fixState, FixState.searching);
      const fresh = GnssSnapshot(
        gnssSupported: true,
        timestampMs: 100000,
        location: GnssLocationInfo(latitude: 1, longitude: 2, timeMs: 95000),
      );
      expect(stateOf(fresh).fixState, FixState.fixed);
      expect(stateOf(fresh).fixAgeMs, 5000);
      const old = GnssSnapshot(
        gnssSupported: true,
        timestampMs: 100000,
        location: GnssLocationInfo(latitude: 1, longitude: 2, timeMs: 80000),
      );
      expect(stateOf(old).fixState, FixState.stale);
    });
  });

  group('GnssController', () {
    ProviderContainer makeContainer(FakeAndroidPlatform p) {
      final c = ProviderContainer(overrides: [
        signalPlatformProvider.overrideWithValue(p),
        initialSettingsProvider.overrideWithValue(const AppSettings(updateIntervalMs: 500)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('registers only while the GNSS tab is visible', () async {
      final p = FakeAndroidPlatform();
      final c = makeContainer(p);
      c.listen(gnssControllerProvider, (_, _) {});
      c.read(currentTabProvider.notifier).select(AppTab.settings);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(p.gnssListens, 0);

      c.read(currentTabProvider.notifier).select(AppTab.gnss);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(p.gnssListens, 1);
      expect(c.read(gnssControllerProvider).streaming, isTrue);

      c.read(currentTabProvider.notifier).select(AppTab.wifi);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(p.gnssCancels, 1);
      expect(c.read(gnssControllerProvider).streaming, isFalse);
    });

    test('records derived history and stop clears it', () async {
      final p = FakeAndroidPlatform();
      final c = makeContainer(p);
      c.listen(gnssControllerProvider, (_, _) {});
      c.read(currentTabProvider.notifier).select(AppTab.gnss);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      p.gnssController.add(const GnssSnapshot(
        gnssSupported: true,
        timestampMs: 1000,
        location: GnssLocationInfo(latitude: 1, longitude: 2, horizontalAccuracyM: 6, timeMs: 900),
        satellites: [
          SatelliteInfo(svid: 1, constellation: Constellation.gps, cn0DbHz: 40, usedInFix: true),
          SatelliteInfo(svid: 2, constellation: Constellation.gps, cn0DbHz: 30, usedInFix: false),
          SatelliteInfo(svid: 3, constellation: Constellation.gps, cn0DbHz: 0, usedInFix: false),
        ],
      ));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final h = c.read(historyProvider).series;
      expect(h['gnss.cn0avg']!.single.value, 35);
      expect(h['gnss.used']!.single.value, 1);
      expect(h['gnss.accuracy']!.single.value, 6);
      expect(c.read(gnssControllerProvider).fixState, FixState.fixed);

      c.read(gnssControllerProvider.notifier).stop();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(c.read(historyProvider).series.keys.where((k) => k.startsWith('gnss.')), isEmpty);
      expect(c.read(gnssControllerProvider).status, MonitorStatus.stopped);
      expect(c.read(gnssControllerProvider).snapshot, isNull);
      expect(p.gnssCancels, 1);
    });

    test('sensorVisible is true on the overview tab', () {
      final c = makeContainer(FakeAndroidPlatform());
      expect(c.read(sensorVisibleProvider(Sensor.gnss)), isTrue);
    });
  });
}
