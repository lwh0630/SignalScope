import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/history.dart';
import '../../../core/lifecycle.dart';
import '../../../core/providers.dart';
import '../../../core/utils/throttle.dart';
import '../../../data/models/gnss_info.dart';
import '../../monitoring/monitor_status.dart';
import '../../permissions/application/permission_controller.dart';
import '../data/gnss_repository.dart';

/// What the fix section of the page should say.
enum FixState {
  /// No snapshot yet.
  unknown,

  /// Device has no GNSS receiver.
  unsupported,

  /// Permission / system switch / provider prevents a fix.
  blocked,

  /// Listening but no position received.
  searching,

  /// Fresh position.
  fixed,

  /// A position was received but it is older than [GnssState.staleAfterMs].
  stale,
}

class GnssState {
  const GnssState({
    this.snapshot,
    this.status = MonitorStatus.listening,
    this.streaming = false,
  });

  /// Fixes older than this (relative to the snapshot clock) are shown as stale.
  static const int staleAfterMs = 10000;

  final GnssSnapshot? snapshot;
  final MonitorStatus status;
  final bool streaming;

  FixState get fixState {
    final s = snapshot;
    if (s == null) return FixState.unknown;
    if (s.gnssSupported == false) return FixState.unsupported;
    if (s.issues.any((i) => i == 'no_location_permission' || i == 'location_off' || i == 'gps_provider_disabled')) {
      return FixState.blocked;
    }
    final loc = s.location;
    if (loc == null || !loc.hasFix) return FixState.searching;
    final age = fixAgeMs;
    if (age != null && age > staleAfterMs) return FixState.stale;
    return FixState.fixed;
  }

  /// Snapshot time minus fix time. `null` when either is unknown.
  int? get fixAgeMs {
    final s = snapshot;
    final t = s?.location?.timeMs;
    final now = s?.timestampMs;
    if (t == null || now == null) return null;
    final age = now - t;
    return age < 0 ? 0 : age;
  }

  GnssState copyWith({Object? snapshot = _keep, MonitorStatus? status, bool? streaming}) => GnssState(
        snapshot: identical(snapshot, _keep) ? this.snapshot : snapshot as GnssSnapshot?,
        status: status ?? this.status,
        streaming: streaming ?? this.streaming,
      );
}

const Object _keep = Object();

final gnssRepositoryProvider = Provider<GnssRepository>(
  (ref) => GnssRepository(ref.watch(signalPlatformProvider)),
);

class GnssController extends Notifier<GnssState> {
  StreamSubscription<GnssSnapshot>? _sub;
  late KeyedThrottle<int, GnssSnapshot> _throttle;
  bool _alive = true;

  GnssRepository get _repo => ref.read(gnssRepositoryProvider);

  @override
  GnssState build() {
    _alive = true;
    // Switching platform (demo mode on/off) rebuilds this controller from scratch.
    ref.watch(signalPlatformProvider);
    _throttle = KeyedThrottle<int, GnssSnapshot>(
      interval: () => Duration(milliseconds: ref.read(settingsProvider).updateIntervalMs),
      onValue: (_, snap) => _apply(snap),
    );
    ref.onDispose(() {
      _alive = false;
      _sub?.cancel();
      _sub = null;
      _throttle.dispose();
    });
    ref.listen<bool>(sensorVisibleProvider(Sensor.gnss), (_, _) => _reconcile());
    ref.listen(
      permissionProvider.select((p) => (p.location, p.locationServicesEnabled, p.loaded)),
      (prev, next) {
        // `$3` is `loaded`: the very first load is not a user-visible change.
        if (prev != null && prev.$3 && prev != next && _sub != null) {
          _stopStream();
          _reconcile();
        }
      },
    );
    Future.microtask(_reconcile);
    return const GnssState();
  }

  void start() {
    state = state.copyWith(status: MonitorStatus.listening);
    _reconcile();
  }

  void pause() {
    state = state.copyWith(status: MonitorStatus.paused);
    _reconcile();
  }

  void stop() {
    state = state.copyWith(status: MonitorStatus.stopped, snapshot: null);
    _throttle.clear();
    ref.read(historyProvider.notifier).clearPrefix('gnss.');
    _reconcile();
  }

  void _reconcile() {
    if (!_alive) return;
    final platform = ref.read(signalPlatformProvider);
    final should = platform.isAndroid &&
        ref.read(sensorVisibleProvider(Sensor.gnss)) &&
        state.status == MonitorStatus.listening;
    if (should && _sub == null) {
      _startStream();
    } else if (!should && _sub != null) {
      _stopStream();
    }
  }

  void _startStream() {
    _sub = _repo.snapshotStream().listen(
      (snap) => _throttle.add(0, snap),
      onError: (Object _) {},
    );
    state = state.copyWith(streaming: true);
  }

  void _stopStream() {
    _sub?.cancel();
    _sub = null;
    _throttle.clear();
    if (_alive) state = state.copyWith(streaming: false);
  }

  void _apply(GnssSnapshot snap) {
    if (!_alive) return;
    state = state.copyWith(snapshot: snap);
    final ts = snap.timestampMs;
    final history = ref.read(historyProvider.notifier);
    final avg = GnssRepository.averageCn0(snap.satellites);
    if (avg != null) history.add('gnss.cn0avg', avg, 'dB-Hz', timestampMs: ts);
    if (snap.satellites.isNotEmpty) {
      history.add('gnss.used', snap.usedCount.toDouble(), '', timestampMs: ts);
    }
    final acc = snap.location?.horizontalAccuracyM;
    if (acc != null) history.add('gnss.accuracy', acc, 'm', timestampMs: ts);
  }
}

final gnssControllerProvider = NotifierProvider<GnssController, GnssState>(GnssController.new);
