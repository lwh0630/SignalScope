/// Pure helpers for Wi-Fi data. All outputs are *derived* values computed from
/// frequency / capability strings that Android reported.
library;

enum WifiBand {
  ghz24('2.4 GHz'),
  ghz5('5 GHz'),
  ghz6('6 GHz'),
  unknown('--');

  const WifiBand(this.label);
  final String label;
}

class WifiUtils {
  WifiUtils._();

  static WifiBand bandOf(int? mhz) {
    if (mhz == null) return WifiBand.unknown;
    if (mhz >= 2400 && mhz <= 2500) return WifiBand.ghz24;
    if (mhz >= 4900 && mhz < 5925) return WifiBand.ghz5;
    if (mhz >= 5925 && mhz <= 7125) return WifiBand.ghz6;
    return WifiBand.unknown;
  }

  /// IEEE 802.11 channel number from centre frequency, `null` if out of range.
  static int? channelOf(int? mhz) {
    if (mhz == null) return null;
    if (mhz == 2484) return 14;
    if (mhz >= 2412 && mhz <= 2472) return (mhz - 2407) ~/ 5;
    if (mhz >= 5160 && mhz < 5925) return (mhz - 5000) ~/ 5;
    if (mhz >= 5955 && mhz <= 7115) return (mhz - 5950) ~/ 5;
    if (mhz == 5935) return 2; // 6 GHz channel 2
    return null;
  }

  /// `ScanResult.CHANNEL_WIDTH_*` to MHz (80+80 reported as 160).
  static int? widthMhz(int? code) {
    switch (code) {
      case 0:
        return 20;
      case 1:
        return 40;
      case 2:
        return 80;
      case 3:
      case 4:
        return 160;
      case 5:
        return 320;
      default:
        return null;
    }
  }

  /// Classic AOSP mapping of RSSI to a 0..100 percentage
  /// (-100 dBm = 0 %, -55 dBm = 100 %). This is a derived display value.
  static int percentFromRssi(int rssi) {
    const minRssi = -100;
    const maxRssi = -55;
    if (rssi <= minRssi) return 0;
    if (rssi >= maxRssi) return 100;
    return ((rssi - minRssi) * 100 / (maxRssi - minRssi)).round();
  }

  /// 0..4 bars from RSSI.
  static int barsFromRssi(int? rssi) {
    if (rssi == null) return 0;
    if (rssi >= -55) return 4;
    if (rssi >= -67) return 3;
    if (rssi >= -78) return 2;
    if (rssi >= -90) return 1;
    return 0;
  }

  /// Security label parsed from `ScanResult.capabilities`.
  /// Returns `null` for an empty capability string.
  static String? securityFromCapabilities(String? cap) {
    if (cap == null || cap.isEmpty) return null;
    final c = cap.toUpperCase();
    final parts = <String>[];
    if (c.contains('SAE')) {
      parts.add('WPA3');
    }
    if (c.contains('WPA2')) {
      parts.add('WPA2');
    }
    if (c.contains('WPA-') || c.contains('[WPA]')) {
      parts.add('WPA');
    }
    if (c.contains('WEP')) {
      parts.add('WEP');
    }
    if (c.contains('OWE') && !c.contains('OWE_TRANSITION')) {
      parts.add('OWE');
    }
    if (c.contains('EAP')) {
      parts.add('802.1X');
    }
    if (parts.isEmpty) return 'Open';
    return parts.join('/');
  }

  /// `WifiInfo.SECURITY_TYPE_*` names (API 31+).
  static String? securityTypeName(int? type) {
    switch (type) {
      case 0:
        return 'Open';
      case 1:
        return 'WEP';
      case 2:
        return 'WPA/WPA2-PSK';
      case 3:
        return 'EAP';
      case 4:
        return 'WPA3-SAE';
      case 5:
        return 'WPA3-Enterprise 192-bit';
      case 6:
        return 'OWE';
      case 7:
        return 'WAPI-PSK';
      case 8:
        return 'WAPI-Cert';
      case 9:
        return 'WPA3-Enterprise';
      case 10:
      case 11:
        return 'Passpoint';
      case 12:
        return 'DPP';
      default:
        return null;
    }
  }

  /// `ScanResult.WIFI_STANDARD_*` / `WifiInfo.getWifiStandard()` names.
  static String? standardName(int? s) {
    switch (s) {
      case 1:
        return '802.11a/b/g';
      case 4:
        return 'Wi-Fi 4 (802.11n)';
      case 5:
        return 'Wi-Fi 5 (802.11ac)';
      case 6:
        return 'Wi-Fi 6 (802.11ax)';
      case 7:
        return '802.11ad';
      case 8:
        return 'Wi-Fi 7 (802.11be)';
      default:
        return null;
    }
  }
}
