import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/history.dart';
import '../../../core/lifecycle.dart';
import '../../../core/providers.dart';
import '../../../core/utils/throttle.dart';
import '../../../data/models/cellular_event.dart';
import '../../../data/models/cellular_info.dart';
import '../../../data/models/sim_info.dart';
import '../../monitoring/monitor_status.dart';
import '../../permissions/application/permission_controller.dart';
import '../data/cellular_repository.dart';

export '../../monitoring/monitor_status.dart';

class CellularState {
  const CellularState({
    this.sims = const [],
    this.simsLoaded = false,
    this.selectedSubId,
    this.status = MonitorStatus.listening,
    this.streaming = false,
    this.latest = const {},
    this.errorCode,
  });

  final List<SimInfo> sims;
  final bool simsLoaded;
  final int? selectedSubId;
  final MonitorStatus status;

  /// Native listeners are currently registered.
  final bool streaming;

  /// Independent latest snapshot per subscription id.
  final Map<int, CellularInfo> latest;
  final String? errorCode;

  SimInfo? get selectedSim {
    for (final s in sims) {
      if (s.subscriptionId == selectedSubId) return s;
    }
    return null;
  }

  CellularInfo? get selectedInfo => selectedSubId == null ? null : latest[selectedSubId];

  CellularState copyWith({
    List<SimInfo>? sims,
    bool? simsLoaded,
    Object? selectedSubId = _keep,
    MonitorStatus? status,
    bool? streaming,
    Map<int, CellularInfo>? latest,
    Object? errorCode = _keep,
  }) =>
      CellularState(
        sims: sims ?? this.sims,
        simsLoaded: simsLoaded ?? this.simsLoaded,
        selectedSubId: identical(selectedSubId, _keep) ? this.selectedSubId : selectedSubId as int?,
        status: status ?? this.status,
        streaming: streaming ?? this.streaming,
        latest: latest ?? this.latest,
        errorCode: identical(errorCode, _keep) ? this.errorCode : errorCode as String?,
      );
}

const Object _keep = Object();

final cellularRepositoryProvider = Provider<CellularRepository>(
  (ref) => CellularRepository(ref.watch(signalPlatformProvider)),
);

class CellularController extends Notifier<CellularState> {
  StreamSubscription<CellularEvent>? _sub;
  late KeyedThrottle<int, CellularInfo> _throttle;
  bool _alive = true;

  CellularRepository get _repo => ref.read(cellularRepositoryProvider);

  @override
  CellularState build() {
    _alive = true;
    // Switching platform (demo mode on/off) rebuilds this controller from scratch.
    ref.watch(signalPlatformProvider);
    _throttle = KeyedThrottle<int, CellularInfo>(
      interval: () => Duration(milliseconds: ref.read(settingsProvider).updateIntervalMs),
      onValue: (_, info) => _apply(info),
    );
    ref.onDispose(() {
      _alive = false;
      _sub?.cancel();
      _sub = null;
      _throttle.dispose();
    });
    ref.listen<bool>(sensorVisibleProvider(Sensor.cellular), (_, _) => _reconcile());
    ref.listen(
      permissionProvider.select((p) => (p.phone, p.location, p.loaded)),
      (prev, next) {
        // The very first load is not a change; the SIM list is already being read.
        if (prev != null && prev.$3 && prev != next) refreshSims();
      },
    );
    Future.microtask(refreshSims);
    return const CellularState();
  }

  // ---- user actions ----

  Future<void> start() async {
    state = state.copyWith(status: MonitorStatus.listening);
    await refreshSims();
    _reconcile();
  }

  void pause() {
    state = state.copyWith(status: MonitorStatus.paused);
    _reconcile();
  }

  /// Ends the session: unregisters listeners and discards live data + history.
  void stop() {
    state = state.copyWith(status: MonitorStatus.stopped, latest: const {});
    _throttle.clear();
    ref.read(historyProvider.notifier).clearPrefix('cell.');
    _reconcile();
  }

  void selectSim(int subscriptionId) {
    state = state.copyWith(selectedSubId: subscriptionId);
  }

  /// Re-reads the SIM list and restarts native listeners if the set changed.
  Future<void> refreshSims() async {
    final sims = await _repo.loadSims();
    if (!_alive) return;
    final oldIds = state.sims.map((s) => s.subscriptionId).toList();
    final newIds = sims.map((s) => s.subscriptionId).toList();

    int? selected = state.selectedSubId;
    if (selected == null || !newIds.contains(selected)) {
      selected = null;
      for (final s in sims) {
        if (s.isDefaultData) selected = s.subscriptionId;
      }
      selected ??= sims.isEmpty ? null : sims.first.subscriptionId;
    }
    // Drop data of SIMs that are gone so it is never shown for another card.
    final latest = {
      for (final e in state.latest.entries)
        if (newIds.contains(e.key)) e.key: e.value,
    };
    state = state.copyWith(
      sims: sims,
      simsLoaded: true,
      selectedSubId: selected,
      latest: latest,
    );
    if (oldIds.join(',') != newIds.join(',')) _stopStream();
    _reconcile();
  }

  // ---- stream management ----

  void _reconcile() {
    if (!_alive) return;
    final platform = ref.read(signalPlatformProvider);
    final shouldStream = platform.isAndroid &&
        ref.read(sensorVisibleProvider(Sensor.cellular)) &&
        state.status == MonitorStatus.listening &&
        state.sims.isNotEmpty;
    if (shouldStream && _sub == null) {
      _startStream();
    } else if (!shouldStream && _sub != null) {
      _stopStream();
    }
  }

  void _startStream() {
    final ids = state.sims.map((s) => s.subscriptionId).toList();
    _sub = _repo.watch(ids).listen(
      _onEvent,
      onError: (Object e) {
        if (_alive) state = state.copyWith(errorCode: 'stream_error');
      },
    );
    state = state.copyWith(streaming: true, errorCode: null);
  }

  void _stopStream() {
    _sub?.cancel();
    _sub = null;
    _throttle.clear();
    if (_alive) state = state.copyWith(streaming: false);
  }

  void _onEvent(CellularEvent event) {
    if (event is SimsChangedEvent) {
      refreshSims();
    } else if (event is CellularSnapshotEvent) {
      _throttle.add(event.info.subscriptionId, event.info);
    }
  }

  void _apply(CellularInfo info) {
    if (!_alive) return;
    if (!state.sims.any((s) => s.subscriptionId == info.subscriptionId)) return;
    state = state.copyWith(latest: {...state.latest, info.subscriptionId: info});
    _record(info);
  }

  void _record(CellularInfo info) {
    final h = ref.read(historyProvider.notifier);
    final p = 'cell.${info.subscriptionId}';
    final ts = info.timestampMs;
    void add(String key, num? v, String unit) {
      if (v != null) h.add('$p.$key', v.toDouble(), unit, timestampMs: ts);
    }

    add('primary', info.gaugeReading?.dbm, 'dBm');
    final lte = info.servingLte;
    add('lte.rsrp', lte?.rsrp, 'dBm');
    add('lte.rsrq', lte?.rsrq, 'dB');
    add('lte.rssnr', lte?.rssnr, 'dB');
    final nr = info.servingNr;
    add('nr.ss_rsrp', nr?.ssRsrp, 'dBm');
    add('nr.ss_rsrq', nr?.ssRsrq, 'dB');
    add('nr.ss_sinr', nr?.ssSinr, 'dB');
  }
}

final cellularControllerProvider =
    NotifierProvider<CellularController, CellularState>(CellularController.new);
