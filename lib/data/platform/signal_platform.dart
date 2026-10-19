import '../models/app_update_info.dart';
import '../models/cellular_event.dart';
import '../models/gnss_info.dart';
import '../models/platform_info.dart';
import '../models/sim_info.dart';
import '../models/wifi_info.dart';

/// Abstraction over the host operating system's signal APIs.
///
/// * Android: implemented with MethodChannel / EventChannel and Kotlin code.
/// * Other platforms (Windows): everything is reported as unsupported; the
///   UI shows an explicit "not supported on this platform" message instead
///   of fabricated data.
abstract class SignalPlatform {
  /// `android`, `windows`, ...
  String get name;

  bool get isAndroid;

  Future<PlatformCapabilities> getCapabilities();

  // ---- permissions & settings shortcuts ----
  Future<PermissionSnapshot> getPermissions();
  Future<PermissionSnapshot> requestPermissions(Set<PermGroup> groups);
  Future<bool> openAppSettings();
  Future<bool> openLocationSettings();
  Future<bool> openWifiSettings();

  // ---- cellular ----
  Future<List<SimInfo>> getSimList();

  /// Emits a snapshot whenever the system reports a change for any of the
  /// given subscriptions. Cancelling the subscription unregisters the native
  /// listeners.
  Stream<CellularEvent> cellularStream(List<int> subscriptionIds);

  // ---- Wi-Fi ----
  Future<WifiConnectionInfo?> getWifiConnection();
  Stream<WifiConnectionInfo> wifiConnectionStream();

  /// Reads the system's cached scan results without starting a new scan.
  Future<WifiScanResult> getWifiScanResults();

  /// Asks the OS to start a scan (subject to system throttling) and returns
  /// the cached results together with the throttling outcome.
  Future<WifiScanResult> requestWifiScan();

  /// Emits whenever the OS publishes new scan results.
  Stream<WifiScanResult> wifiScanStream();

  // ---- GNSS ----
  Stream<GnssSnapshot> gnssStream();

  // ---- storage ----
  Future<String?> loadSettings();
  Future<void> saveSettings(String json);

  /// Saves [content] as a file the user can find; returns a human readable
  /// location, or `null` on failure.
  Future<String?> saveExport(String fileName, String mimeType, String content);

  // ---- app update (Android only; the download itself uses dart:io) ----

  /// Installed version and device ABIs; `null` when unknown / unsupported.
  Future<AppBuildInfo?> getAppBuildInfo();

  /// Empty, app-private directory for the downloaded update APK; `null` when
  /// the platform cannot install updates.
  Future<String?> prepareUpdateDir();

  /// Re-verifies [path] (SHA-256 [sha256], package, newer version, same signing
  /// key) and opens the system installer.
  Future<InstallApkResult> installApk(String path, String sha256);

  /// Opens the system "install unknown apps" screen for this app.
  Future<bool> openInstallPermissionSettings();
}
