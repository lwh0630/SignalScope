import '../../../core/utils/band_lookup.dart';
import '../../../data/models/cell_signal_info.dart';
import '../../../data/models/cellular_event.dart';
import '../../../data/models/cellular_info.dart';
import '../../../data/models/sim_info.dart';
import '../../../data/platform/signal_platform.dart';

/// Reads SIM and cellular data from the platform and post-processes it.
///
/// Post-processing is limited to *deriving* a band from EARFCN / NR-ARFCN when
/// Android did not report one and the channel number is unambiguous.
class CellularRepository {
  CellularRepository(this._platform);

  final SignalPlatform _platform;

  Future<List<SimInfo>> loadSims() => _platform.getSimList();

  Stream<CellularEvent> watch(List<int> subscriptionIds) {
    return _platform.cellularStream(subscriptionIds).map((event) {
      if (event is CellularSnapshotEvent) {
        return CellularSnapshotEvent(resolveBands(event.info));
      }
      return event;
    });
  }

  /// Fills in `bands` for cells where the OS reported none.
  static CellularInfo resolveBands(CellularInfo info) {
    final lte = [
      for (final c in info.lte)
        if (c.bands.isEmpty && c.earfcn != null) _withLteBand(c) else c,
    ];
    final nr = [
      for (final c in info.nr)
        if (c.bands.isEmpty && c.nrarfcn != null) _withNrBand(c) else c,
    ];
    return info.withCells(lte: lte, nr: nr);
  }

  static LteSignalInfo _withLteBand(LteSignalInfo c) {
    final band = BandLookup.lteBandFromEarfcn(c.earfcn);
    return band == null ? c : c.withBands([band], BandSource.derived);
  }

  static NrSignalInfo _withNrBand(NrSignalInfo c) {
    final band = BandLookup.nrBandFromNrarfcn(c.nrarfcn);
    return band == null ? c : c.withBands([band], BandSource.derived);
  }
}
