import 'dart:async';
import 'dart:math' as math;

import '../models/cellular_event.dart';
import '../models/cellular_info.dart';
import '../models/gnss_info.dart';
import '../models/platform_info.dart';
import '../models/sim_info.dart';
import '../models/wifi_info.dart';
import 'signal_platform.dart';

/// Built-in sample data for exploring the UI without a SIM, Wi-Fi or sky view.
///
/// * Only active while the user switches on **Demo mode** (session only, off by default).
/// * Fully deterministic: every value is a plain function of the tick counter.
///   No random numbers, nothing is read from the device.
/// * Operators, addresses and coordinates are fictional (test PLMN 001/01,
///   RFC 5737 addresses, position 0°N 0°E).
/// * Settings and export go through to the real platform.
class DemoPlatform implements SignalPlatform {
  DemoPlatform(this._real);

  final SignalPlatform _real;

  @override
  String get name => 'demo';

  @override
  bool get isAndroid => true;

  @override
  Future<PlatformCapabilities> getCapabilities() async => const PlatformCapabilities(
        platform: 'demo',
        hasTelephony: true,
        hasWifi: true,
        hasGnss: true,
        wifiEnabled: true,
        simCount: 2,
      );

  @override
  Future<PermissionSnapshot> getPermissions() async => _granted;

  @override
  Future<PermissionSnapshot> requestPermissions(Set<PermGroup> groups) async => _granted;

  static const PermissionSnapshot _granted = PermissionSnapshot(
    location: PermStatus.granted,
    phone: PermStatus.granted,
    nearbyWifi: PermStatus.granted,
    locationServicesEnabled: true,
  );

  @override
  Future<bool> openAppSettings() async => false;

  @override
  Future<bool> openLocationSettings() async => false;

  @override
  Future<bool> openWifiSettings() async => false;

  // ---- cellular ----

  @override
  Future<List<SimInfo>> getSimList() async => DemoData.sims;

  @override
  Stream<CellularEvent> cellularStream(List<int> subscriptionIds) =>
      _ticker((tick) {
        // Streams are cancelled with the subscription; one event per SIM per tick.
        return [
          for (final id in subscriptionIds)
            if (DemoData.cellular(id, tick) case final info?) CellularSnapshotEvent(info),
        ];
      });

  // ---- Wi-Fi ----

  @override
  Future<WifiConnectionInfo?> getWifiConnection() async => DemoData.wifiConnection(0);

  @override
  Stream<WifiConnectionInfo> wifiConnectionStream() => _ticker((tick) => [DemoData.wifiConnection(tick)]);

  @override
  Future<WifiScanResult> getWifiScanResults() async => DemoData.wifiScan(0, started: null);

  @override
  Future<WifiScanResult> requestWifiScan() async => DemoData.wifiScan(0, started: true);

  @override
  Stream<WifiScanResult> wifiScanStream() => _ticker((tick) => [DemoData.wifiScan(tick, started: null)], every: 3);

  // ---- GNSS ----

  @override
  Stream<GnssSnapshot> gnssStream() => _ticker((tick) => [DemoData.gnss(tick)]);

  // ---- storage: delegate to the real platform ----

  @override
  Future<String?> loadSettings() => _real.loadSettings();

  @override
  Future<void> saveSettings(String json) => _real.saveSettings(json);

  @override
  Future<String?> saveExport(String fileName, String mimeType, String content) =>
      _real.saveExport(fileName, mimeType, content);

  /// Emits [build] results immediately and then once per second (per [every]
  /// seconds). The timer is cancelled when the listener cancels.
  static Stream<T> _ticker<T>(List<T> Function(int tick) build, {int every = 1}) {
    late StreamController<T> controller;
    Timer? timer;
    var tick = 0;
    void emit() {
      for (final e in build(tick)) {
        controller.add(e);
      }
      tick += every;
    }

    controller = StreamController<T>(
      onListen: () {
        emit();
        timer = Timer.periodic(const Duration(seconds: 1), (_) => emit());
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
      },
    );
    return controller.stream;
  }
}

/// Pure functions producing the sample values. Unit-tested for determinism.
class DemoData {
  DemoData._();

  static int _wave(int tick, double period, double amplitude, {double phase = 0}) =>
      (amplitude * math.sin(tick * 2 * math.pi / period + phase)).round();

  static const List<SimInfo> sims = [
    SimInfo(
      subscriptionId: 1,
      slotIndex: 0,
      displayName: 'Demo SIM A',
      carrierName: 'Demo Carrier A',
      mcc: '001',
      mnc: '01',
      countryIso: 'zz',
      simState: 5,
      simOperator: '00101',
      simOperatorName: 'Demo Carrier A',
      networkOperator: '00101',
      networkOperatorName: 'Demo Carrier A',
      isRoaming: false,
      isEmbedded: false,
      isDefaultData: true,
      isDataEnabled: true,
      dataState: 2,
      dataNetworkType: 13,
      voiceNetworkType: 13,
    ),
    SimInfo(
      subscriptionId: 2,
      slotIndex: 1,
      displayName: 'Demo SIM B',
      carrierName: 'Demo Carrier B',
      mcc: '001',
      mnc: '02',
      countryIso: 'zz',
      simState: 5,
      simOperator: '00102',
      simOperatorName: 'Demo Carrier B',
      networkOperator: '00102',
      networkOperatorName: 'Demo Carrier B',
      isRoaming: false,
      isEmbedded: true,
      isDefaultData: false,
      isDataEnabled: false,
      dataState: 0,
      dataNetworkType: 20,
      voiceNetworkType: 20,
    ),
  ];

  /// SIM 1: LTE anchor with an NR leg (5G NSA). SIM 2: NR standalone.
  static CellularInfo? cellular(int subscriptionId, int tick) {
    final now = DateTime.now().millisecondsSinceEpoch;
    switch (subscriptionId) {
      case 1:
        final rsrp = -92 + _wave(tick, 40, 8);
        return CellularInfo.fromMap({
          'subscriptionId': 1,
          'timestampMs': now,
          'signalLevel': 3,
          'serviceState': 0,
          'operatorName': 'Demo Carrier A',
          'networkOperator': '00101',
          'isRoaming': false,
          'dataNetworkType': 13,
          'voiceNetworkType': 13,
          'hasDataNetwork': true,
          'ipv4': '198.51.100.23', // RFC 5737 documentation range
          'ipv6': ['2001:db8:1::a1b2'], // RFC 3849 documentation prefix
          'ipv6LinkLocal': ['fe80::1'],
          'overrideNetworkType': 3, // NR_NSA
          'primaryRat': 'LTE',
          'primaryDbm': rsrp,
          'cellInfoAvailable': true,
          'lte': [
            {
              'isRegistered': true,
              'source': 'cellInfo',
              'rsrp': rsrp,
              'rsrq': -10 + _wave(tick, 30, 2),
              'rssi': -65 + _wave(tick, 50, 3),
              'rssnr': 12 + _wave(tick, 35, 4),
              'cqi': 11,
              'level': 3,
              'dbm': rsrp,
              'pci': 301,
              'tac': 4660,
              'ci': 28901377,
              'earfcn': 1850,
              'bandwidthKhz': 20000,
              'bands': [3],
              'mcc': '001',
              'mnc': '01',
            },
            {
              'isRegistered': false,
              'source': 'cellInfo',
              'rsrp': -104 + _wave(tick, 45, 3),
              'rsrq': -14,
              'pci': 302,
              'earfcn': 1850,
              'level': 1,
            },
            {
              'isRegistered': false,
              'source': 'cellInfo',
              'rsrp': -110 + _wave(tick, 55, 3),
              'rsrq': -16,
              'pci': 417,
              'earfcn': 3725,
              'level': 1,
            },
          ],
          'nr': [
            {
              'isRegistered': true,
              'source': 'signalStrength',
              'ssRsrp': -98 + _wave(tick, 42, 6, phase: 1),
              'ssRsrq': -11,
              'ssSinr': 14 + _wave(tick, 38, 3),
              'level': 3,
              'dbm': -98,
            },
          ],
          'legacy': <Object?>[],
          'issues': <String>[],
        });
      case 2:
        final ssRsrp = -85 + _wave(tick, 36, 6, phase: 2);
        return CellularInfo.fromMap({
          'subscriptionId': 2,
          'timestampMs': now,
          'signalLevel': 4,
          'serviceState': 0,
          'operatorName': 'Demo Carrier B',
          'networkOperator': '00102',
          'isRoaming': false,
          'dataNetworkType': 20,
          'voiceNetworkType': 20,
          // Not the default data SIM: no mobile-data network of its own.
          'hasDataNetwork': false,
          'ipv6': <String>[],
          'ipv6LinkLocal': <String>[],
          'primaryRat': 'NR',
          'primaryDbm': ssRsrp,
          'cellInfoAvailable': true,
          'lte': <Object?>[],
          'nr': [
            {
              'isRegistered': true,
              'source': 'cellInfo',
              'ssRsrp': ssRsrp,
              'ssRsrq': -9 + _wave(tick, 28, 2),
              'ssSinr': 20 + _wave(tick, 33, 4),
              'csiRsrp': ssRsrp + 2,
              'level': 4,
              'dbm': ssRsrp,
              'nrarfcn': 633984,
              'pci': 55,
              'tac': 9999,
              'nci': 5000123456,
              'bands': [78],
              'mcc': '001',
              'mnc': '02',
            },
          ],
          'legacy': <Object?>[],
          'issues': <String>[],
        });
      default:
        return null;
    }
  }

  static WifiConnectionInfo wifiConnection(int tick) {
    return WifiConnectionInfo.fromMap({
      'timestampMs': DateTime.now().millisecondsSinceEpoch,
      'wifiEnabled': true,
      'connected': true,
      'ssid': 'DemoNet-5G',
      'bssid': '02:00:00:aa:bb:01',
      'rssi': -55 + _wave(tick, 30, 6),
      'frequencyMhz': 5180,
      'linkSpeedMbps': 866,
      'txLinkSpeedMbps': 866,
      'rxLinkSpeedMbps': 780,
      'ipAddress': '192.0.2.10',
      'ipv6': ['2001:db8:2::10'],
      'ipv6LinkLocal': ['fe80::10'],
      // Like a real Android 10+ device the demo does not know the device MAC.
      'gateway': '192.0.2.1',
      'dns': ['192.0.2.1'],
      'securityType': 4,
      'wifiStandard': 6,
      'channelWidthCode': 2,
      'issues': <String>[],
    });
  }

  static const List<(String, String, int, int, int, String)> _aps = [
    // ssid, bssid, base rssi, frequency MHz, width code, capabilities
    ('DemoNet-5G', '02:00:00:aa:bb:01', -55, 5180, 2, '[WPA3-SAE-CCMP][ESS]'),
    ('DemoNet', '02:00:00:aa:bb:02', -48, 2437, 1, '[WPA2-PSK-CCMP][ESS]'),
    ('Neighbour-2G', '02:00:00:cc:dd:03', -72, 2412, 0, '[WPA2-PSK-CCMP][ESS]'),
    ('CafeGuest', '02:00:00:cc:dd:04', -78, 2462, 0, '[ESS]'),
    ('Neighbour-5G', '02:00:00:cc:dd:05', -81, 5240, 1, '[WPA2-PSK-CCMP][ESS]'),
    ('Office-5G', '02:00:00:ee:ff:06', -66, 5745, 2, '[WPA2-EAP/SHA1-CCMP][ESS]'),
    ('DemoNet-6G', '02:00:00:aa:bb:07', -70, 6055, 3, '[WPA3-SAE-CCMP][ESS]'),
    ('', '02:00:00:cc:dd:08', -85, 2447, 0, '[WPA2-PSK-CCMP][ESS]'),
  ];

  static const Map<int, int> _centers = {
    2437: 2447, // 40 MHz: channels 6 + 10
    5180: 5210, // 80 MHz: channels 36-48
    5240: 5230, // 40 MHz: channels 44 + 48
    5745: 5775, // 80 MHz: channels 149-161
    6055: 6105, // 160 MHz block in 6 GHz
  };

  static WifiScanResult wifiScan(int tick, {required bool? started}) {
    return WifiScanResult.fromMap({
      'timestampMs': DateTime.now().millisecondsSinceEpoch,
      'scanStarted': started,
      'throttled': false,
      'issues': <String>[],
      'results': [
        for (var i = 0; i < _aps.length; i++)
          {
            'bssid': _aps[i].$2,
            'ssid': _aps[i].$1.isEmpty ? null : _aps[i].$1,
            'rssi': _aps[i].$3 + _wave(tick, 24 + i * 3, 3, phase: i.toDouble()),
            'frequencyMhz': _aps[i].$4,
            // Wide channels are centred on the middle of their block, not on the primary channel.
            'centerFreq0Mhz': _centers[_aps[i].$4],
            'channelWidthCode': _aps[i].$5,
            'capabilities': _aps[i].$6,
            'wifiStandard': _aps[i].$4 > 5900 ? 6 : 5,
          },
      ],
    });
  }

  // constellation code, svid, base azimuth, elevation
  static const List<(int, int, double, double)> _sats = [
    (1, 3, 20, 62),
    (1, 8, 110, 35),
    (1, 14, 200, 71),
    (1, 22, 290, 18),
    (1, 27, 340, 48),
    (3, 5, 60, 41),
    (3, 12, 150, 25),
    (3, 18, 250, 8),
    (5, 6, 90, 55),
    (5, 9, 180, 30),
    (5, 23, 270, 66),
    (5, 28, 320, 12),
    (6, 2, 45, 52),
    (6, 11, 135, 22),
    (6, 19, 225, 38),
    (4, 1, 300, 5),
  ];

  static GnssSnapshot gnss(int tick) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final sats = <Map<String, Object?>>[];
    for (final s in _sats) {
      final az = (s.$3 + tick * 0.25) % 360;
      final el = s.$4;
      // Signal grows with elevation; the lowest satellites are not tracked at all.
      final tracked = el >= 10;
      final cn0 = tracked ? 22 + el * 0.28 + 2.5 * math.sin(tick * 0.4 + s.$2) : 0.0;
      sats.add({
        'svid': s.$2,
        'constellation': s.$1,
        'azimuthDeg': az,
        'elevationDeg': el,
        'cn0DbHz': double.parse(cn0.toStringAsFixed(1)),
        'usedInFix': tracked && cn0 >= 28,
      });
    }
    return GnssSnapshot.fromMap({
      'timestampMs': now,
      'gnssSupported': true,
      'providerEnabled': true,
      'engineStarted': true,
      'ttffMs': 6400,
      'location': {
        'latitude': 0.0,
        'longitude': 0.0,
        'altitudeM': 12.0 + _wave(tick, 60, 1),
        'horizontalAccuracyM': 4.0 + _wave(tick, 20, 1),
        'verticalAccuracyM': 6.0,
        'speedMps': 0.0,
        'timeMs': now,
        'provider': 'demo',
        'isMock': false,
      },
      'satellites': sats,
      'issues': <String>[],
    });
  }
}
