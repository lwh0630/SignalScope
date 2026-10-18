import '../../core/utils/wifi_utils.dart';
import 'model_utils.dart';

/// State of the currently connected Wi-Fi network.
class WifiConnectionInfo {
  const WifiConnectionInfo({
    required this.timestampMs,
    this.wifiEnabled,
    this.connected = false,
    this.ssid,
    this.bssid,
    this.rssi,
    this.frequencyMhz,
    this.linkSpeedMbps,
    this.txLinkSpeedMbps,
    this.rxLinkSpeedMbps,
    this.ipAddress,
    this.ipv6 = const [],
    this.ipv6LinkLocal = const [],
    this.macAddress,
    this.gateway,
    this.dns = const [],
    this.securityType,
    this.capabilities,
    this.wifiStandard,
    this.channelWidthCode,
    this.issues = const [],
  });

  final int timestampMs;
  final bool? wifiEnabled;
  final bool connected;
  final String? ssid;
  final String? bssid;

  /// dBm
  final int? rssi;

  /// MHz
  final int? frequencyMhz;

  /// Mbps
  final int? linkSpeedMbps;
  final int? txLinkSpeedMbps;
  final int? rxLinkSpeedMbps;
  final String? ipAddress;

  /// Global / unique-local IPv6 addresses of the Wi-Fi link (no `fe80::`).
  final List<String> ipv6;

  /// Link-local (`fe80::`) addresses, kept apart because they are not routable.
  final List<String> ipv6LinkLocal;

  /// Device Wi-Fi MAC. Android 10+ hides it from apps, so this is usually
  /// `null`; it is never filled with the `02:00:00:00:00:00` placeholder.
  final String? macAddress;
  final String? gateway;
  final List<String> dns;

  /// `WifiInfo.SECURITY_TYPE_*` (API 31+).
  final int? securityType;

  /// Capability string of the matching scan result (used when
  /// [securityType] is unavailable and for channel width).
  final String? capabilities;
  final int? wifiStandard;

  /// `ScanResult.CHANNEL_WIDTH_*` of the matching scan result.
  final int? channelWidthCode;
  final List<String> issues;

  WifiBand get band => WifiUtils.bandOf(frequencyMhz);
  int? get channel => WifiUtils.channelOf(frequencyMhz);
  int? get channelWidthMhz => WifiUtils.widthMhz(channelWidthCode);
  int? get percent => rssi == null ? null : WifiUtils.percentFromRssi(rssi!);
  String? get securityLabel =>
      WifiUtils.securityTypeName(securityType) ??
      WifiUtils.securityFromCapabilities(capabilities);
  String? get standardLabel => WifiUtils.standardName(wifiStandard);

  factory WifiConnectionInfo.fromMap(Map<Object?, Object?> m) => WifiConnectionInfo(
        timestampMs: asInt(m['timestampMs']) ?? DateTime.now().millisecondsSinceEpoch,
        wifiEnabled: asBool(m['wifiEnabled']),
        connected: asBool(m['connected']) ?? false,
        ssid: asString(m['ssid']),
        bssid: asString(m['bssid']),
        rssi: asInt(m['rssi']),
        frequencyMhz: asInt(m['frequencyMhz']),
        linkSpeedMbps: asInt(m['linkSpeedMbps']),
        txLinkSpeedMbps: asInt(m['txLinkSpeedMbps']),
        rxLinkSpeedMbps: asInt(m['rxLinkSpeedMbps']),
        ipAddress: asString(m['ipAddress']),
        ipv6: asStringList(m['ipv6']),
        ipv6LinkLocal: asStringList(m['ipv6LinkLocal']),
        macAddress: asString(m['macAddress']),
        gateway: asString(m['gateway']),
        dns: asStringList(m['dns']),
        securityType: asInt(m['securityType']),
        capabilities: asString(m['capabilities']),
        wifiStandard: asInt(m['wifiStandard']),
        channelWidthCode: asInt(m['channelWidthCode']),
        issues: asStringList(m['issues']),
      );

  Map<String, Object?> toMap() => {
        'timestampMs': timestampMs,
        'wifiEnabled': wifiEnabled,
        'connected': connected,
        'ssid': ssid,
        'bssid': bssid,
        'rssi_dBm': rssi,
        'frequency_MHz': frequencyMhz,
        'channel_derived': channel,
        'band_derived': band.label,
        'signalPercent_derived': percent,
        'linkSpeed_Mbps': linkSpeedMbps,
        'txLinkSpeed_Mbps': txLinkSpeedMbps,
        'rxLinkSpeed_Mbps': rxLinkSpeedMbps,
        'ipv4': ipAddress,
        'ipv6': ipv6,
        'ipv6LinkLocal': ipv6LinkLocal,
        'deviceMac': macAddress,
        'routerBssid': bssid,
        'gateway': gateway,
        'dns': dns,
        'security': securityLabel,
        'wifiStandard': standardLabel,
        'channelWidth_MHz': channelWidthMhz,
        'issues': issues,
      };
}

/// One access point from the system scan cache.
class WifiScanInfo {
  const WifiScanInfo({
    required this.bssid,
    this.ssid,
    this.rssi,
    this.frequencyMhz,
    this.centerFreq0Mhz,
    this.centerFreq1Mhz,
    this.channelWidthCode,
    this.capabilities,
    this.wifiStandard,
    this.timestampUs,
  });

  final String bssid;

  /// `null` for hidden networks or when the OS withholds the SSID.
  final String? ssid;
  final int? rssi;
  final int? frequencyMhz;
  final int? centerFreq0Mhz;
  final int? centerFreq1Mhz;
  final int? channelWidthCode;
  final String? capabilities;
  final int? wifiStandard;

  /// Time since boot in microseconds when the result was last seen.
  final int? timestampUs;

  WifiBand get band => WifiUtils.bandOf(frequencyMhz);
  int? get channel => WifiUtils.channelOf(frequencyMhz);
  int? get channelWidthMhz => WifiUtils.widthMhz(channelWidthCode);
  String? get securityLabel => WifiUtils.securityFromCapabilities(capabilities);
  String? get standardLabel => WifiUtils.standardName(wifiStandard);
  int get bars => WifiUtils.barsFromRssi(rssi);

  factory WifiScanInfo.fromMap(Map<Object?, Object?> m) => WifiScanInfo(
        bssid: asString(m['bssid']) ?? '--',
        ssid: asString(m['ssid']),
        rssi: asInt(m['rssi']),
        frequencyMhz: asInt(m['frequencyMhz']),
        centerFreq0Mhz: asInt(m['centerFreq0Mhz']),
        centerFreq1Mhz: asInt(m['centerFreq1Mhz']),
        channelWidthCode: asInt(m['channelWidthCode']),
        capabilities: asString(m['capabilities']),
        wifiStandard: asInt(m['wifiStandard']),
        timestampUs: asInt(m['timestampUs']),
      );

  Map<String, Object?> toMap() => {
        'ssid': ssid,
        'bssid': bssid,
        'rssi_dBm': rssi,
        'frequency_MHz': frequencyMhz,
        'channel_derived': channel,
        'band_derived': band.label,
        'channelWidth_MHz': channelWidthMhz,
        'security_derived': securityLabel,
        'capabilities': capabilities,
        'wifiStandard': standardLabel,
      };
}

/// Result of reading the cached scan list.
class WifiScanResult {
  const WifiScanResult({
    required this.results,
    this.scanStarted,
    this.throttled = false,
    this.issues = const [],
    this.timestampMs,
    this.retryAfterMs,
  });

  final List<WifiScanInfo> results;

  /// Whether `WifiManager.startScan()` accepted the last request.
  final bool? scanStarted;

  /// True when the OS refused a scan because of throttling.
  final bool throttled;
  final List<String> issues;
  final int? timestampMs;

  /// When throttled by our own scan budget: ms until another scan may be requested.
  final int? retryAfterMs;

  factory WifiScanResult.fromMap(Map<Object?, Object?> m) => WifiScanResult(
        results: asMapList(m['results']).map(WifiScanInfo.fromMap).toList(growable: false),
        scanStarted: asBool(m['scanStarted']),
        throttled: asBool(m['throttled']) ?? false,
        issues: asStringList(m['issues']),
        timestampMs: asInt(m['timestampMs']),
        retryAfterMs: asInt(m['retryAfterMs']),
      );
}
