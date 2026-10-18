import '../../../data/models/gnss_info.dart';
import '../../../data/platform/signal_platform.dart';

class GnssRepository {
  GnssRepository(this._platform);

  final SignalPlatform _platform;

  /// Location + satellite snapshots. Cancelling the subscription unregisters
  /// the native `LocationManager` / `GnssStatus` listeners.
  Stream<GnssSnapshot> snapshotStream() => _platform.gnssStream();

  /// Mean C/N0 (dB-Hz) of the satellites that are actually being tracked
  /// (C/N0 > 0). Derived value; `null` when nothing is tracked.
  static double? averageCn0(Iterable<SatelliteInfo> sats) {
    var sum = 0.0;
    var n = 0;
    for (final s in sats) {
      final v = s.cn0DbHz;
      if (v != null && v > 0) {
        sum += v;
        n++;
      }
    }
    return n == 0 ? null : sum / n;
  }

  /// Satellites with a positive C/N0.
  static int trackedCount(Iterable<SatelliteInfo> sats) =>
      sats.where((s) => (s.cn0DbHz ?? 0) > 0).length;
}
