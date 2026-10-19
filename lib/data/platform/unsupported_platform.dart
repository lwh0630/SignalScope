import 'dart:convert';
import 'dart:io';

import '../models/app_update_info.dart';
import '../models/cellular_event.dart';
import '../models/gnss_info.dart';
import '../models/platform_info.dart';
import '../models/sim_info.dart';
import '../models/wifi_info.dart';
import 'signal_platform.dart';

/// Platform for hosts without native signal collectors (currently Windows).
///
/// All signal queries return "nothing available". Only local settings
/// persistence and CSV/JSON export are functional.
class UnsupportedPlatform implements SignalPlatform {
  UnsupportedPlatform(this.name);

  @override
  final String name;

  @override
  bool get isAndroid => false;

  @override
  Future<PlatformCapabilities> getCapabilities() async =>
      PlatformCapabilities.unsupported(name);

  @override
  Future<PermissionSnapshot> getPermissions() async =>
      const PermissionSnapshot.unsupported();

  @override
  Future<PermissionSnapshot> requestPermissions(Set<PermGroup> groups) async =>
      const PermissionSnapshot.unsupported();

  @override
  Future<bool> openAppSettings() async => false;

  @override
  Future<bool> openLocationSettings() async => false;

  @override
  Future<bool> openWifiSettings() async => false;

  @override
  Future<List<SimInfo>> getSimList() async => const [];

  @override
  Stream<CellularEvent> cellularStream(List<int> subscriptionIds) =>
      const Stream.empty();

  @override
  Future<WifiConnectionInfo?> getWifiConnection() async => null;

  @override
  Stream<WifiConnectionInfo> wifiConnectionStream() => const Stream.empty();

  @override
  Future<WifiScanResult> getWifiScanResults() async =>
      const WifiScanResult(results: [], issues: ['platform_unsupported']);

  @override
  Future<WifiScanResult> requestWifiScan() async =>
      const WifiScanResult(results: [], issues: ['platform_unsupported']);

  @override
  Stream<WifiScanResult> wifiScanStream() => const Stream.empty();

  @override
  Stream<GnssSnapshot> gnssStream() => const Stream.empty();

  File? _settingsFile() {
    final base =
        Platform.environment['APPDATA'] ??
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'];
    if (base == null) return null;
    return File(
      '$base${Platform.pathSeparator}SignalScope${Platform.pathSeparator}settings.json',
    );
  }

  @override
  Future<String?> loadSettings() async {
    try {
      final f = _settingsFile();
      if (f == null || !await f.exists()) return null;
      return await f.readAsString();
    } on Object {
      return null;
    }
  }

  @override
  Future<void> saveSettings(String json) async {
    try {
      final f = _settingsFile();
      if (f == null) return;
      await f.parent.create(recursive: true);
      await f.writeAsString(json);
    } on Object {
      // Persisting settings is best-effort.
    }
  }

  @override
  Future<AppBuildInfo?> getAppBuildInfo() async => null;

  @override
  Future<String?> prepareUpdateDir() async => null;

  @override
  Future<InstallApkResult> installApk(String path, String sha256) async =>
      InstallApkResult.failed;

  @override
  Future<bool> openInstallPermissionSettings() async => false;

  @override
  Future<String?> saveExport(
    String fileName,
    String mimeType,
    String content,
  ) async {
    try {
      final home =
          Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (home == null) return null;
      final dir = Directory('$home${Platform.pathSeparator}Downloads');
      await dir.create(recursive: true);
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsString(content, encoding: utf8);
      return file.path;
    } on Object {
      return null;
    }
  }
}
