import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/signal_history_point.dart';
import 'providers.dart';

class HistoryState {
  const HistoryState(this.series);

  /// Series key -> chronological samples.
  final Map<String, List<SignalHistoryPoint>> series;
}

/// Bounded in-memory sample store.
///
/// Every series keeps at most [retentionMs] of data (5 minutes) and at most
/// [maxPointsPerSeries] points, so memory use is constant regardless of how
/// long the app runs.
class HistoryNotifier extends Notifier<HistoryState> {
  static const int retentionMs = 300000;
  static const int maxPointsPerSeries = 700;

  @override
  HistoryState build() => const HistoryState({});

  void add(String series, double value, String unit, {int? timestampMs}) {
    if (!ref.read(settingsProvider).recordHistory) return;
    final ts = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
    final old = state.series[series] ?? const <SignalHistoryPoint>[];
    final next = <SignalHistoryPoint>[
      ...old,
      SignalHistoryPoint(
        timestampMs: ts,
        series: series,
        value: value,
        unit: unit,
      ),
    ];
    final cutoff = ts - retentionMs;
    var start = 0;
    while (start < next.length - 1 && next[start].timestampMs < cutoff) {
      start++;
    }
    if (next.length - start > maxPointsPerSeries) {
      start = next.length - maxPointsPerSeries;
    }
    final trimmed = start == 0 ? next : next.sublist(start);
    state = HistoryState({...state.series, series: trimmed});
  }

  /// Removes every series whose key starts with [prefix].
  void clearPrefix(String prefix) {
    state = HistoryState({
      for (final e in state.series.entries)
        if (!e.key.startsWith(prefix)) e.key: e.value,
    });
  }

  void clearAll() => state = const HistoryState({});

  List<SignalHistoryPoint> all() =>
      [for (final list in state.series.values) ...list]
        ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
}

final historyProvider = NotifierProvider<HistoryNotifier, HistoryState>(
  HistoryNotifier.new,
);

const List<SignalHistoryPoint> _emptySeries = [];

/// Samples of one series; rebuilds only when that series changes.
final historySeriesProvider = Provider.family<List<SignalHistoryPoint>, String>(
  (ref, key) {
    return ref.watch(
      historyProvider.select((s) => s.series[key] ?? _emptySeries),
    );
  },
);
