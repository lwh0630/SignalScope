import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/history.dart';
import '../../../core/lifecycle.dart';
import '../../../core/providers.dart';
import '../../../core/utils/throttle.dart';
import '../../../core/utils/wifi_utils.dart';
import '../../../data/models/wifi_info.dart';
import '../../monitoring/monitor_status.dart';
import '../../permissions/application/permission_controller.dart';
import '../data/wifi_repository.dart';

/// Result of the last explicit scan request, for user feedback.
enum ScanNotice { none, requested, refusedByOs, budgetUsed }

class WifiState {
  const WifiState({
    this.connection,
    this.scan,
    this.status = MonitorStatus.listening,
    this.streaming = false,
    this.scanning = false,
    this.notice = ScanNotice.none,
    this.retryAfterSeconds,
    this.bandFilter,
    this.sort = WifiSort.signal,
  });

  final WifiConnectionInfo? connection;
  final WifiScanResult? scan;
  final MonitorStatus status;
  final bool streaming;
  final bool scanning;
  final ScanNotice notice;
  final int? retryAfterSeconds;

  /// `null` shows all bands.
  final WifiBand? bandFilter;
  final WifiSort sort;

  List<WifiScanInfo> get visibleAps => WifiRepository.filterAndSort(
        scan?.results ?? const [],
        band: bandFilter,
        sort: sort,
      );

  WifiState copyWith({
    Object? connection = _keep,
    Object? scan = _keep,
    MonitorStatus? status,
    bool? streaming,
    bool? scanning,
    ScanNotice? notice,
    Object? retryAfterSeconds = _keep,
    Object? bandFilter = _keep,
    WifiSort? sort,
  }) =>
      WifiState(
        connection: identical(connection, _keep) ? this.connection : connection as WifiConnectionInfo?,
        scan: identical(scan, _keep) ? this.scan : scan as WifiScanResult?,
        status: status ?? this.status,
        streaming: streaming ?? this.streaming,
        scanning: scanning ?? this.scanning,
        notice: notice ?? this.notice,
        retryAfterSeconds:
            identical(retryAfterSeconds, _keep) ? this.retryAfterSeconds : retryAfterSeconds as int?,
        bandFilter: identical(bandFilter, _keep) ? this.bandFilter : bandFilter as WifiBand?,
        sort: sort ?? this.sort,
      );
}

const Object _keep = Object();

final wifiRepositoryProvider = Provider<WifiRepository>(
  (ref) => WifiRepository(ref.watch(signalPlatformProvider)),
);

class WifiController extends Notifier<WifiState> {
  StreamSubscription<WifiConnectionInfo>? _connSub;
  StreamSubscription<WifiScanResult>? _scanSub;
  late KeyedThrottle<int, WifiConnectionInfo> _throttle;
  bool _alive = true;

  WifiRepository get _repo => ref.read(wifiRepositoryProvider);

  @override
  WifiState build() {
    _alive = true;
    // Switching platform (demo mode on/off) rebuilds this controller from scratch.
    ref.watch(signalPlatformProvider);
    _throttle = KeyedThrottle<int, WifiConnectionInfo>(
      interval: () => Duration(milliseconds: ref.read(settingsProvider).updateIntervalMs),
      onValue: (_, info) => _applyConnection(info),
    );
    ref.onDispose(() {
      _alive = false;
      _connSub?.cancel();
      _scanSub?.cancel();
      _connSub = null;
      _scanSub = null;
      _throttle.dispose();
    });
    ref.listen<bool>(sensorVisibleProvider(Sensor.wifi), (_, _) => _reconcile());
    ref.listen(
      permissionProvider.select((p) => (p.location, p.nearbyWifi, p.locationServicesEnabled, p.loaded)),
      (prev, next) {
        // `$4` is `loaded`: the very first load is not a user-visible change.
        if (prev != null && prev.$4 && prev != next && _connSub != null) {
          // Permission or location switch changed: re-register to pick up newly allowed data.
          _stopStreams();
          _reconcile();
        }
      },
    );
    Future.microtask(_reconcile);
    return const WifiState();
  }

  // ---- user actions ----

  void start() {
    state = state.copyWith(status: MonitorStatus.listening);
    _reconcile();
  }

  void pause() {
    state = state.copyWith(status: MonitorStatus.paused);
    _reconcile();
  }

  void stop() {
    state = state.copyWith(status: MonitorStatus.stopped, connection: null, scan: null);
    _throttle.clear();
    ref.read(historyProvider.notifier).clearPrefix('wifi.');
    _reconcile();
  }

  void setBandFilter(WifiBand? band) => state = state.copyWith(bandFilter: band);

  void setSort(WifiSort sort) => state = state.copyWith(sort: sort);

  /// Asks the OS for a fresh scan (throttled by Android and by our own budget).
  Future<void> requestScan() async {
    if (state.scanning) return;
    state = state.copyWith(scanning: true, notice: ScanNotice.none);
    final result = await _repo.requestScan();
    if (!_alive) return;
    final ScanNotice notice;
    int? retry;
    if (result.throttled && result.retryAfterMs != null) {
      notice = ScanNotice.budgetUsed;
      retry = (result.retryAfterMs! / 1000).ceil();
    } else if (result.scanStarted == false) {
      notice = ScanNotice.refusedByOs;
    } else {
      notice = ScanNotice.requested;
    }
    state = state.copyWith(
      scanning: false,
      notice: notice,
      retryAfterSeconds: retry,
      scan: result.results.isEmpty && state.scan != null && result.issues.isNotEmpty ? state.scan : result,
    );
  }

  // ---- stream management ----

  void _reconcile() {
    if (!_alive) return;
    final platform = ref.read(signalPlatformProvider);
    final should = platform.isAndroid &&
        ref.read(sensorVisibleProvider(Sensor.wifi)) &&
        state.status == MonitorStatus.listening;
    if (should && _connSub == null) {
      _startStreams();
    } else if (!should && _connSub != null) {
      _stopStreams();
    }
  }

  void _startStreams() {
    _connSub = _repo.connectionStream().listen(
      (info) => _throttle.add(0, info),
      onError: (Object _) {},
    );
    _scanSub = _repo.scanStream().listen(
      (scan) {
        if (_alive) state = state.copyWith(scan: scan);
      },
      onError: (Object _) {},
    );
    state = state.copyWith(streaming: true);
  }

  void _stopStreams() {
    _connSub?.cancel();
    _scanSub?.cancel();
    _connSub = null;
    _scanSub = null;
    _throttle.clear();
    if (_alive) state = state.copyWith(streaming: false);
  }

  void _applyConnection(WifiConnectionInfo info) {
    if (!_alive) return;
    state = state.copyWith(connection: info);
    final rssi = info.rssi;
    if (info.connected && rssi != null) {
      ref.read(historyProvider.notifier).add(
            'wifi.rssi',
            rssi.toDouble(),
            'dBm',
            timestampMs: info.timestampMs,
          );
    }
  }
}

final wifiControllerProvider = NotifierProvider<WifiController, WifiState>(WifiController.new);
