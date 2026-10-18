import 'package:flutter_application/core/history.dart';
import 'package:flutter_application/core/providers.dart';
import 'package:flutter_application/core/utils/band_lookup.dart';
import 'package:flutter_application/core/utils/network_type.dart';
import 'package:flutter_application/core/utils/throttle.dart';
import 'package:flutter_application/data/models/cell_signal_info.dart';
import 'package:flutter_application/data/models/cellular_event.dart';
import 'package:flutter_application/data/models/cellular_info.dart';
import 'package:flutter_application/data/models/sim_info.dart';
import 'package:flutter_application/features/cellular/application/cellular_controller.dart';
import 'package:flutter_application/features/cellular/data/cellular_repository.dart';
import 'package:flutter_application/features/settings/domain/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LTE model', () {
    test('eNodeB id is derived from ECI and unavailable stays null', () {
      const lte = LteSignalInfo(ci: 0x1234567);
      expect(lte.enbId, 0x12345);
      expect(lte.localCellId, 0x67);
      expect(const LteSignalInfo().enbId, isNull);
      expect(const LteSignalInfo().localCellId, isNull);
    });

    test('fromMap keeps nulls and never turns them into 0', () {
      final lte = LteSignalInfo.fromMap({'rsrp': -95, 'rsrq': null, 'pci': 120});
      expect(lte.rsrp, -95);
      expect(lte.rsrq, isNull);
      expect(lte.rssnr, isNull);
      expect(lte.pci, 120);
      expect(lte.bands, isEmpty);
      expect(lte.bandSource, isNull);
    });
  });

  group('band lookup', () {
    test('LTE EARFCN maps to a unique band', () {
      expect(BandLookup.lteBandFromEarfcn(1300), 3);
      expect(BandLookup.lteBandFromEarfcn(100), 1);
      expect(BandLookup.lteBandFromEarfcn(38950), 40);
      expect(BandLookup.lteBandFromEarfcn(40936), 41);
      expect(BandLookup.lteBandFromEarfcn(6300), 20);
      expect(BandLookup.lteBandFromEarfcn(9999999), isNull);
      expect(BandLookup.lteBandFromEarfcn(null), isNull);
    });

    test('LTE downlink frequency formula', () {
      // Band 3, EARFCN 1300: 1805 + 0.1 * (1300 - 1200) = 1815 MHz
      expect(BandLookup.lteDlFrequencyMhz(1300), closeTo(1815.0, 0.001));
    });

    test('NR-ARFCN to frequency (global raster)', () {
      expect(BandLookup.nrFrequencyMhz(632628), closeTo(3489.42, 0.01)); // n78 example
      expect(BandLookup.nrFrequencyMhz(154810), closeTo(774.05, 0.01));
      expect(BandLookup.nrFrequencyMhz(2054166), closeTo(24250.08 + 0.06 * (2054166 - 2016667), 0.01));
      expect(BandLookup.nrFrequencyMhz(null), isNull);
    });

    test('ambiguous NR frequency does not yield a band', () {
      // 3489.42 MHz lies in both n77 and n78.
      expect(BandLookup.nrBandCandidates(632628), containsAll([77, 78]));
      expect(BandLookup.nrBandFromNrarfcn(632628), isNull);
      // 774 MHz: n28 only (n12/n14 end at 746/768, n29 is 717-728).
      expect(BandLookup.nrBandCandidates(154810), [28]);
      expect(BandLookup.nrBandFromNrarfcn(154810), 28);
    });
  });

  group('network type / NSA-SA', () {
    test('generation mapping', () {
      expect(NetworkTypes.generation(13), NetworkGeneration.g4);
      expect(NetworkTypes.generation(20), NetworkGeneration.g5);
      expect(NetworkTypes.generation(3), NetworkGeneration.g3);
      expect(NetworkTypes.generation(1), NetworkGeneration.g2);
      expect(NetworkTypes.generation(0), NetworkGeneration.none);
      expect(NetworkTypes.generation(null), NetworkGeneration.none);
    });

    test('NSA/SA only when public data is sufficient', () {
      expect(NetworkTypes.nrMode(dataNetworkType: 20), 'SA');
      expect(NetworkTypes.nrMode(dataNetworkType: 13, overrideNetworkType: 3), 'NSA');
      expect(NetworkTypes.nrMode(dataNetworkType: 13, overrideNetworkType: 5), 'NSA');
      expect(NetworkTypes.nrMode(dataNetworkType: 13, overrideNetworkType: 0), isNull);
      expect(NetworkTypes.nrMode(dataNetworkType: 13), isNull);
      expect(NetworkTypes.nrMode(dataNetworkType: 3, overrideNetworkType: 3), isNull);
    });
  });

  group('CellularInfo', () {
    test('LTE values are never presented as NR', () {
      const info = CellularInfo(
        subscriptionId: 1,
        timestampMs: 0,
        dataNetworkType: 13,
        overrideNetworkType: 3,
        lte: [LteSignalInfo(isRegistered: true, rsrp: -90, pci: 10)],
      );
      expect(info.nrMode, 'NSA');
      expect(info.servingNr, isNull);
      expect(info.gaugeReading?.rat, 'LTE');
      expect(info.gaugeReading?.dbm, -90);
    });

    test('NR gauge on SA uses SS-RSRP, falling back to CSI-RSRP', () {
      const sa = CellularInfo(
        subscriptionId: 1,
        timestampMs: 0,
        dataNetworkType: 20,
        nr: [NrSignalInfo(isRegistered: true, ssRsrp: -85, csiRsrp: -88)],
      );
      expect(sa.gaugeReading?.metric, 'SS-RSRP');
      const csiOnly = CellularInfo(
        subscriptionId: 1,
        timestampMs: 0,
        dataNetworkType: 20,
        nr: [NrSignalInfo(isRegistered: true, csiRsrp: -88)],
      );
      expect(csiOnly.gaugeReading?.metric, 'CSI-RSRP');
      expect(csiOnly.gaugeReading?.dbm, -88);
    });

    test('neighbours exclude serving and signal-only entries', () {
      const info = CellularInfo(
        subscriptionId: 1,
        timestampMs: 0,
        lte: [
          LteSignalInfo(isRegistered: true, pci: 1),
          LteSignalInfo(isRegistered: false, pci: 2),
          LteSignalInfo(isRegistered: null, source: CellDataSource.signalStrength, rsrp: -100),
        ],
      );
      expect(info.neighborLte.map((c) => c.pci), [2]);
      expect(info.servingLte?.pci, 1);
    });

    test('no reading yields null, not 0', () {
      const info = CellularInfo(subscriptionId: 1, timestampMs: 0);
      expect(info.gaugeReading, isNull);
    });
  });

  group('repository band resolution', () {
    test('keeps reported bands, derives only when missing and unique', () {
      const info = CellularInfo(
        subscriptionId: 1,
        timestampMs: 0,
        lte: [
          LteSignalInfo(earfcn: 1300), // no bands -> derive B3
          LteSignalInfo(earfcn: 1300, bands: [1], bandSource: BandSource.reported),
          LteSignalInfo(), // nothing to derive from
        ],
        nr: [
          NrSignalInfo(nrarfcn: 632628), // ambiguous n77/n78
          NrSignalInfo(nrarfcn: 154810), // unique n28
        ],
      );
      final out = CellularRepository.resolveBands(info);
      expect(out.lte[0].bands, [3]);
      expect(out.lte[0].bandSource, BandSource.derived);
      expect(out.lte[1].bands, [1]);
      expect(out.lte[1].bandSource, BandSource.reported);
      expect(out.lte[2].bands, isEmpty);
      expect(out.nr[0].bands, isEmpty);
      expect(out.nr[1].bands, [28]);
      expect(out.nr[1].bandSource, BandSource.derived);
    });
  });

  group('KeyedThrottle', () {
    testWidgets('delivers first value immediately and the newest per window', (tester) async {
      final got = <int>[];
      final t = KeyedThrottle<int, int>(
        interval: () => const Duration(milliseconds: 500),
        onValue: (_, v) => got.add(v),
      );
      t.add(1, 1);
      t.add(1, 2);
      t.add(1, 3);
      expect(got, [1]);
      await tester.pump(const Duration(milliseconds: 500));
      expect(got, [1, 3]);
      await tester.pump(const Duration(milliseconds: 500));
      expect(got, [1, 3]); // nothing pending -> nothing delivered
      t.add(1, 4);
      expect(got, [1, 3, 4]);
      t.add(2, 9); // other key has its own window
      expect(got.last, 9);
      t.dispose();
    });
  });

  group('CellularController', () {
    const sim1 = SimInfo(subscriptionId: 11, slotIndex: 0, carrierName: 'A', isDefaultData: false);
    const sim2 = SimInfo(subscriptionId: 22, slotIndex: 1, carrierName: 'B', isDefaultData: true);

    ProviderContainer makeContainer(FakeAndroidPlatform p) {
      final c = ProviderContainer(overrides: [
        signalPlatformProvider.overrideWithValue(p),
        initialSettingsProvider.overrideWithValue(const AppSettings(updateIntervalMs: 500)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('keeps independent state per SIM and selects the default data SIM', () async {
      final platform = FakeAndroidPlatform()..sims = [sim1, sim2];
      final c = makeContainer(platform);
      c.listen(cellularControllerProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));

      var s = c.read(cellularControllerProvider);
      expect(s.sims.length, 2);
      expect(s.selectedSubId, 22);
      expect(platform.lastSubscriptionIds, [11, 22]);

      platform.cellularController.add(const CellularSnapshotEvent(CellularInfo(
        subscriptionId: 11,
        timestampMs: 1000,
        dataNetworkType: 13,
        lte: [LteSignalInfo(isRegistered: true, rsrp: -100)],
      )));
      platform.cellularController.add(const CellularSnapshotEvent(CellularInfo(
        subscriptionId: 22,
        timestampMs: 1000,
        dataNetworkType: 13,
        lte: [LteSignalInfo(isRegistered: true, rsrp: -80)],
      )));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      s = c.read(cellularControllerProvider);
      expect(s.latest[11]!.servingLte!.rsrp, -100);
      expect(s.latest[22]!.servingLte!.rsrp, -80);
      expect(s.selectedInfo!.servingLte!.rsrp, -80);

      c.read(cellularControllerProvider.notifier).selectSim(11);
      expect(c.read(cellularControllerProvider).selectedInfo!.servingLte!.rsrp, -100);

      // history was recorded per subscription
      final h = c.read(historyProvider);
      expect(h.series['cell.11.primary']!.single.value, -100);
      expect(h.series['cell.22.primary']!.single.value, -80);
    });

    test('pause unregisters native listeners, resume registers again, stop clears data', () async {
      final platform = FakeAndroidPlatform()..sims = [sim1];
      final c = makeContainer(platform);
      c.listen(cellularControllerProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final ctrl = c.read(cellularControllerProvider.notifier);
      expect(c.read(cellularControllerProvider).streaming, isTrue);

      platform.cellularController.add(const CellularSnapshotEvent(CellularInfo(
        subscriptionId: 11,
        timestampMs: 1,
        lte: [LteSignalInfo(isRegistered: true, rsrp: -90)],
        dataNetworkType: 13,
      )));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      ctrl.pause();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.read(cellularControllerProvider).streaming, isFalse);
      expect(platform.cellularCancels, 1);
      // data is kept while paused
      expect(c.read(cellularControllerProvider).latest.containsKey(11), isTrue);

      await ctrl.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.read(cellularControllerProvider).streaming, isTrue);

      ctrl.stop();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final s = c.read(cellularControllerProvider);
      expect(s.status, MonitorStatus.stopped);
      expect(s.streaming, isFalse);
      expect(s.latest, isEmpty);
      expect(c.read(historyProvider).series.keys.where((k) => k.startsWith('cell.')), isEmpty);
    });

    test('no SIM leaves state empty without starting a stream', () async {
      final platform = FakeAndroidPlatform();
      final c = makeContainer(platform);
      c.listen(cellularControllerProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final s = c.read(cellularControllerProvider);
      expect(s.simsLoaded, isTrue);
      expect(s.sims, isEmpty);
      expect(s.streaming, isFalse);
      expect(platform.cellularListens, 0);
    });
  });
}
