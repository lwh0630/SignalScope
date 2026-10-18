/// One sample of a signal series, used for charts and CSV/JSON export.
///
/// [series] identifies the quantity, e.g. `cell.3.lte.rsrp`, `wifi.rssi`,
/// `gnss.cn0avg`. [value] keeps the raw unit named in [unit].
class SignalHistoryPoint {
  const SignalHistoryPoint({
    required this.timestampMs,
    required this.series,
    required this.value,
    required this.unit,
  });

  final int timestampMs;
  final String series;
  final double value;
  final String unit;

  Map<String, Object?> toMap() => {
    'timestampMs': timestampMs,
    'time': DateTime.fromMillisecondsSinceEpoch(timestampMs).toIso8601String(),
    'series': series,
    'value': value,
    'unit': unit,
  };
}
