import '../../../core/utils/wifi_utils.dart';
import '../../../data/models/wifi_info.dart';
import '../../../data/platform/signal_platform.dart';

enum WifiSort { signal, channel, name }

class WifiRepository {
  WifiRepository(this._platform);

  final SignalPlatform _platform;

  Future<WifiConnectionInfo?> connectionSnapshot() => _platform.getWifiConnection();

  Stream<WifiConnectionInfo> connectionStream() => _platform.wifiConnectionStream();

  /// Fires whenever the OS publishes new scan results (cache read only).
  Stream<WifiScanResult> scanStream() => _platform.wifiScanStream();

  /// Asks the OS for a scan; subject to Android's throttling.
  Future<WifiScanResult> requestScan() => _platform.requestWifiScan();

  /// Filters by [band] (null = all) and sorts. Entries without RSSI go last.
  static List<WifiScanInfo> filterAndSort(
    List<WifiScanInfo> input, {
    WifiBand? band,
    WifiSort sort = WifiSort.signal,
  }) {
    final list = [
      for (final r in input)
        if (band == null || r.band == band) r,
    ];
    int cmpRssi(WifiScanInfo a, WifiScanInfo b) {
      final ra = a.rssi;
      final rb = b.rssi;
      if (ra == null && rb == null) return 0;
      if (ra == null) return 1;
      if (rb == null) return -1;
      return rb.compareTo(ra);
    }

    switch (sort) {
      case WifiSort.signal:
        list.sort(cmpRssi);
      case WifiSort.channel:
        list.sort((a, b) {
          final ca = a.frequencyMhz ?? 1 << 30;
          final cb = b.frequencyMhz ?? 1 << 30;
          final c = ca.compareTo(cb);
          return c != 0 ? c : cmpRssi(a, b);
        });
      case WifiSort.name:
        list.sort((a, b) {
          final na = (a.ssid ?? '\uffff').toLowerCase();
          final nb = (b.ssid ?? '\uffff').toLowerCase();
          final c = na.compareTo(nb);
          return c != 0 ? c : cmpRssi(a, b);
        });
    }
    return list;
  }
}
