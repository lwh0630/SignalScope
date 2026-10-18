import 'package:flutter_application/core/history.dart';
import 'package:flutter_application/core/providers.dart';
import 'package:flutter_application/core/utils/wifi_utils.dart';
import 'package:flutter_application/data/models/wifi_info.dart';
import 'package:flutter_application/features/settings/domain/app_settings.dart';
import 'package:flutter_application/features/wifi/application/wifi_controller.dart';
import 'package:flutter_application/features/wifi/data/wifi_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WifiUtils', () {
    test('band and channel from frequency', () {
      expect(WifiUtils.bandOf(2437), WifiBand.ghz24);
      expect(WifiUtils.bandOf(5180), WifiBand.ghz5);
      expect(WifiUtils.bandOf(5955), WifiBand.ghz6);
      expect(WifiUtils.bandOf(null), WifiBand.unknown);
      expect(WifiUtils.channelOf(2412), 1);
      expect(WifiUtils.channelOf(2437), 6);
      expect(WifiUtils.channelOf(2484), 14);
      expect(WifiUtils.channelOf(5180), 36);
      expect(WifiUtils.channelOf(5745), 149);
      expect(WifiUtils.channelOf(5955), 1);
      expect(WifiUtils.channelOf(6415), 93);
      expect(WifiUtils.channelOf(null), isNull);
    });

    test('percent mapping is monotonic and clamped', () {
      expect(WifiUtils.percentFromRssi(-120), 0);
      expect(WifiUtils.percentFromRssi(-100), 0);
      expect(WifiUtils.percentFromRssi(-55), 100);
      expect(WifiUtils.percentFromRssi(-30), 100);
      expect(WifiUtils.percentFromRssi(-70), 67);
      expect(WifiUtils.percentFromRssi(-60) > WifiUtils.percentFromRssi(-80), isTrue);
    });

    test('security parsing from capability strings', () {
      expect(WifiUtils.securityFromCapabilities('[WPA2-PSK-CCMP][RSN-PSK-CCMP][ESS]'), 'WPA2');
      expect(WifiUtils.securityFromCapabilities('[RSN-SAE-CCMP][ESS][MFPR]'), 'WPA3');
      expect(WifiUtils.securityFromCapabilities('[RSN-PSK-CCMP+SAE][WPA2-PSK-CCMP][ESS]'), 'WPA3/WPA2');
      expect(WifiUtils.securityFromCapabilities('[WEP][ESS]'), 'WEP');
      expect(WifiUtils.securityFromCapabilities('[ESS]'), 'Open');
      expect(WifiUtils.securityFromCapabilities(null), isNull);
      expect(WifiUtils.securityFromCapabilities(''), isNull);
    });

    test('width and standard codes', () {
      expect(WifiUtils.widthMhz(0), 20);
      expect(WifiUtils.widthMhz(2), 80);
      expect(WifiUtils.widthMhz(3), 160);
      expect(WifiUtils.widthMhz(null), isNull);
      expect(WifiUtils.standardName(6), 'Wi-Fi 6 (802.11ax)');
      expect(WifiUtils.standardName(0), isNull);
    });
  });

  group('WifiRepository.filterAndSort', () {
    const a = WifiScanInfo(bssid: 'a', ssid: 'Alpha', rssi: -70, frequencyMhz: 2412);
    const b = WifiScanInfo(bssid: 'b', ssid: 'beta', rssi: -50, frequencyMhz: 5180);
    const c = WifiScanInfo(bssid: 'c', ssid: null, rssi: -60, frequencyMhz: 5955);
    const d = WifiScanInfo(bssid: 'd', ssid: 'Delta', rssi: null, frequencyMhz: 2437);
    final all = [a, b, c, d];

    test('sorts by signal, strongest first, unknown RSSI last', () {
      final out = WifiRepository.filterAndSort(all);
      expect(out.map((e) => e.bssid), ['b', 'c', 'a', 'd']);
    });

    test('filters by band', () {
      expect(WifiRepository.filterAndSort(all, band: WifiBand.ghz24).map((e) => e.bssid), ['a', 'd']);
      expect(WifiRepository.filterAndSort(all, band: WifiBand.ghz5).map((e) => e.bssid), ['b']);
      expect(WifiRepository.filterAndSort(all, band: WifiBand.ghz6).map((e) => e.bssid), ['c']);
    });

    test('sorts by channel and name', () {
      expect(WifiRepository.filterAndSort(all, sort: WifiSort.channel).map((e) => e.bssid),
          ['a', 'd', 'b', 'c']);
      expect(WifiRepository.filterAndSort(all, sort: WifiSort.name).map((e) => e.bssid),
          ['a', 'b', 'd', 'c']);
    });
  });

  group('WifiConnectionInfo', () {
    test('missing values stay null and derived values are computed', () {
      final w = WifiConnectionInfo.fromMap({
        'connected': true,
        'ssid': 'Home',
        'rssi': -60,
        'frequencyMhz': 5180,
        'capabilities': '[RSN-SAE-CCMP][ESS]',
        'channelWidthCode': 2,
      });
      expect(w.channel, 36);
      expect(w.band, WifiBand.ghz5);
      expect(w.channelWidthMhz, 80);
      expect(w.securityLabel, 'WPA3');
      expect(w.linkSpeedMbps, isNull);
      expect(w.ipAddress, isNull);
      expect(w.dns, isEmpty);
      expect(w.percent, 89); // (-60 - -100) / 45 = 88.9 %
    });

    test('security type from API 31 wins over capability parsing', () {
      final w = WifiConnectionInfo.fromMap({
        'connected': true,
        'securityType': 4,
        'capabilities': '[WPA2-PSK-CCMP]',
      });
      expect(w.securityLabel, 'WPA3-SAE');
    });
  });

  group('WifiController', () {
    ProviderContainer makeContainer(FakeAndroidPlatform p) {
      final c = ProviderContainer(overrides: [
        signalPlatformProvider.overrideWithValue(p),
        initialSettingsProvider.overrideWithValue(const AppSettings(updateIntervalMs: 500)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('streams connection + scans, records RSSI history, pause unregisters', () async {
      final p = FakeAndroidPlatform();
      final c = makeContainer(p);
      c.listen(wifiControllerProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(p.wifiListens, 1);
      expect(c.read(wifiControllerProvider).streaming, isTrue);

      p.wifiController.add(const WifiConnectionInfo(
        timestampMs: 5000,
        connected: true,
        ssid: 'Home',
        rssi: -61,
        frequencyMhz: 5180,
      ));
      p.wifiScanController.add(const WifiScanResult(results: [
        WifiScanInfo(bssid: 'x', rssi: -40, frequencyMhz: 2412),
        WifiScanInfo(bssid: 'y', rssi: -80, frequencyMhz: 5180),
      ]));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final s = c.read(wifiControllerProvider);
      expect(s.connection!.rssi, -61);
      expect(s.visibleAps.map((e) => e.bssid), ['x', 'y']);
      expect(c.read(historyProvider).series['wifi.rssi']!.single.value, -61);

      c.read(wifiControllerProvider.notifier).setBandFilter(WifiBand.ghz5);
      expect(c.read(wifiControllerProvider).visibleAps.map((e) => e.bssid), ['y']);

      c.read(wifiControllerProvider.notifier).pause();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(p.wifiCancels, 1);
      expect(c.read(wifiControllerProvider).streaming, isFalse);
    });

    test('scan request outcome is reported', () async {
      final p = FakeAndroidPlatform()
        ..scanResult = const WifiScanResult(results: [], scanStarted: false, throttled: true, retryAfterMs: 30500);
      final c = makeContainer(p);
      c.listen(wifiControllerProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await c.read(wifiControllerProvider.notifier).requestScan();
      final s = c.read(wifiControllerProvider);
      expect(p.scanRequests, 1);
      expect(s.notice, ScanNotice.budgetUsed);
      expect(s.retryAfterSeconds, 31);
    });
  });
}
