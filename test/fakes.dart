import 'dart:async';

import 'package:flutter_application/data/models/cellular_event.dart';
import 'package:flutter_application/data/models/gnss_info.dart';
import 'package:flutter_application/data/models/platform_info.dart';
import 'package:flutter_application/data/models/sim_info.dart';
import 'package:flutter_application/data/models/wifi_info.dart';
import 'package:flutter_application/data/platform/unsupported_platform.dart';

/// Test double that behaves like Android but returns only what a test feeds in.
class FakeAndroidPlatform extends UnsupportedPlatform {
  FakeAndroidPlatform() : super('android');

  List<SimInfo> sims = const [];
  PermissionSnapshot permissions = const PermissionSnapshot(
    location: PermStatus.granted,
    phone: PermStatus.granted,
    nearbyWifi: PermStatus.granted,
    locationServicesEnabled: true,
  );
  WifiConnectionInfo? wifiConnection;
  WifiScanResult scanResult = const WifiScanResult(results: []);
  String? exported;

  final cellularController = StreamController<CellularEvent>.broadcast();
  final wifiController = StreamController<WifiConnectionInfo>.broadcast();
  final wifiScanController = StreamController<WifiScanResult>.broadcast();
  final gnssController = StreamController<GnssSnapshot>.broadcast();

  int cellularListens = 0;
  int cellularCancels = 0;
  int gnssListens = 0;
  int gnssCancels = 0;
  int wifiListens = 0;
  int wifiCancels = 0;
  int scanRequests = 0;
  List<int>? lastSubscriptionIds;

  @override
  bool get isAndroid => true;

  @override
  Future<PlatformCapabilities> getCapabilities() async =>
      const PlatformCapabilities(
        platform: 'android',
        sdkInt: 34,
        hasTelephony: true,
        hasWifi: true,
        hasGnss: true,
      );

  @override
  Future<PermissionSnapshot> getPermissions() async => permissions;

  @override
  Future<PermissionSnapshot> requestPermissions(Set<PermGroup> groups) async =>
      permissions;

  @override
  Future<List<SimInfo>> getSimList() async => sims;

  @override
  Stream<CellularEvent> cellularStream(List<int> subscriptionIds) {
    lastSubscriptionIds = subscriptionIds;
    late StreamController<CellularEvent> c;
    c = StreamController<CellularEvent>(
      onListen: () {
        cellularListens++;
      },
      onCancel: () {
        cellularCancels++;
      },
    );
    final sub = cellularController.stream.listen(c.add);
    c.onCancel = () async {
      cellularCancels++;
      await sub.cancel();
    };
    return c.stream;
  }

  @override
  Future<WifiConnectionInfo?> getWifiConnection() async => wifiConnection;

  @override
  Stream<WifiConnectionInfo> wifiConnectionStream() {
    late StreamController<WifiConnectionInfo> c;
    c = StreamController<WifiConnectionInfo>();
    wifiListens++;
    final sub = wifiController.stream.listen(c.add);
    c.onCancel = () async {
      wifiCancels++;
      await sub.cancel();
    };
    return c.stream;
  }

  @override
  Future<WifiScanResult> getWifiScanResults() async => scanResult;

  @override
  Future<WifiScanResult> requestWifiScan() async {
    scanRequests++;
    return scanResult;
  }

  @override
  Stream<WifiScanResult> wifiScanStream() {
    late StreamController<WifiScanResult> c;
    c = StreamController<WifiScanResult>();
    final sub = wifiScanController.stream.listen(c.add);
    c.onCancel = () => sub.cancel();
    return c.stream;
  }

  @override
  Stream<GnssSnapshot> gnssStream() {
    late StreamController<GnssSnapshot> c;
    c = StreamController<GnssSnapshot>();
    gnssListens++;
    final sub = gnssController.stream.listen(c.add);
    c.onCancel = () async {
      gnssCancels++;
      await sub.cancel();
    };
    return c.stream;
  }

  @override
  Future<String?> saveExport(
    String fileName,
    String mimeType,
    String content,
  ) async {
    exported = content;
    return 'Download/SignalScope/$fileName';
  }

  @override
  Future<String?> loadSettings() async => null;

  @override
  Future<void> saveSettings(String json) async {}
}
