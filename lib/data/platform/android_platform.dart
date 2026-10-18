import 'package:flutter/services.dart';

import '../models/cellular_event.dart';
import '../models/cellular_info.dart';
import '../models/gnss_info.dart';
import '../models/model_utils.dart';
import '../models/platform_info.dart';
import '../models/sim_info.dart';
import '../models/wifi_info.dart';
import 'signal_platform.dart';

/// Android implementation backed by the Kotlin `NativeChannelHandler`.
class AndroidPlatform implements SignalPlatform {
  AndroidPlatform({
    MethodChannel? method,
    EventChannel? cellular,
    EventChannel? wifi,
    EventChannel? wifiScan,
    EventChannel? gnss,
  })  : _method = method ?? const MethodChannel('signalscope/method'),
        _cellular = cellular ?? const EventChannel('signalscope/cellular'),
        _wifi = wifi ?? const EventChannel('signalscope/wifi'),
        _wifiScan = wifiScan ?? const EventChannel('signalscope/wifi_scan'),
        _gnss = gnss ?? const EventChannel('signalscope/gnss');

  final MethodChannel _method;
  final EventChannel _cellular;
  final EventChannel _wifi;
  final EventChannel _wifiScan;
  final EventChannel _gnss;

  @override
  String get name => 'android';

  @override
  bool get isAndroid => true;

  Future<Map<Object?, Object?>?> _invokeMap(String method, [Object? args]) async {
    try {
      final r = await _method.invokeMethod<Object?>(method, args);
      return r is Map ? r.cast<Object?, Object?>() : null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> _invokeBool(String method) async {
    try {
      return await _method.invokeMethod<bool>(method) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<PlatformCapabilities> getCapabilities() async {
    final m = await _invokeMap('getCapabilities');
    return m == null
        ? const PlatformCapabilities(platform: 'android')
        : PlatformCapabilities.fromMap(m);
  }

  @override
  Future<PermissionSnapshot> getPermissions() async {
    final m = await _invokeMap('getPermissions');
    return m == null ? const PermissionSnapshot() : PermissionSnapshot.fromMap(m);
  }

  @override
  Future<PermissionSnapshot> requestPermissions(Set<PermGroup> groups) async {
    final m = await _invokeMap('requestPermissions', {
      'groups': groups.map((g) => g.name).toList(),
    });
    return m == null ? await getPermissions() : PermissionSnapshot.fromMap(m);
  }

  @override
  Future<bool> openAppSettings() => _invokeBool('openAppSettings');

  @override
  Future<bool> openLocationSettings() => _invokeBool('openLocationSettings');

  @override
  Future<bool> openWifiSettings() => _invokeBool('openWifiSettings');

  @override
  Future<List<SimInfo>> getSimList() async {
    try {
      final r = await _method.invokeMethod<Object?>('getSimList');
      return asMapList(r).map(SimInfo.fromMap).toList(growable: false);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Stream<CellularEvent> cellularStream(List<int> subscriptionIds) {
    return _cellular
        .receiveBroadcastStream({'subscriptionIds': subscriptionIds})
        .map<CellularEvent?>((event) {
          if (event is! Map) return null;
          final m = event.cast<Object?, Object?>();
          if (m['type'] == 'simsChanged') return const SimsChangedEvent();
          return CellularSnapshotEvent(CellularInfo.fromMap(m));
        })
        .where((e) => e != null)
        .cast<CellularEvent>();
  }

  @override
  Future<WifiConnectionInfo?> getWifiConnection() async {
    final m = await _invokeMap('getWifiConnection');
    return m == null ? null : WifiConnectionInfo.fromMap(m);
  }

  @override
  Stream<WifiConnectionInfo> wifiConnectionStream() {
    return _wifi
        .receiveBroadcastStream()
        .where((e) => e is Map)
        .map((e) => WifiConnectionInfo.fromMap((e as Map).cast<Object?, Object?>()));
  }

  @override
  Future<WifiScanResult> getWifiScanResults() async {
    final m = await _invokeMap('getWifiScanResults');
    return m == null
        ? const WifiScanResult(results: [], issues: ['native_error'])
        : WifiScanResult.fromMap(m);
  }

  @override
  Future<WifiScanResult> requestWifiScan() async {
    final m = await _invokeMap('requestWifiScan');
    return m == null
        ? const WifiScanResult(results: [], issues: ['native_error'])
        : WifiScanResult.fromMap(m);
  }

  @override
  Stream<WifiScanResult> wifiScanStream() {
    return _wifiScan
        .receiveBroadcastStream()
        .where((e) => e is Map)
        .map((e) => WifiScanResult.fromMap((e as Map).cast<Object?, Object?>()));
  }

  @override
  Stream<GnssSnapshot> gnssStream() {
    return _gnss
        .receiveBroadcastStream()
        .where((e) => e is Map)
        .map((e) => GnssSnapshot.fromMap((e as Map).cast<Object?, Object?>()));
  }

  @override
  Future<String?> loadSettings() async {
    try {
      return await _method.invokeMethod<String>('loadSettings');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> saveSettings(String json) async {
    try {
      await _method.invokeMethod<void>('saveSettings', {'json': json});
    } on PlatformException {
      // best effort
    } on MissingPluginException {
      // best effort
    }
  }

  @override
  Future<String?> saveExport(String fileName, String mimeType, String content) async {
    try {
      return await _method.invokeMethod<String>('saveExport', {
        'fileName': fileName,
        'mimeType': mimeType,
        'content': content,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
