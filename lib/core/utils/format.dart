/// Formatting helpers. Missing values always render as `--`, never as 0.
library;

const String kUnavailable = '--';

String fmtNum(num? v, {String unit = '', int decimals = 0}) {
  if (v == null) return kUnavailable;
  final s = decimals == 0 ? v.round().toString() : v.toStringAsFixed(decimals);
  return unit.isEmpty ? s : '$s $unit';
}

String fmtText(String? v) => (v == null || v.isEmpty) ? kUnavailable : v;

String fmtBool(bool? v, {required String yes, required String no}) {
  if (v == null) return kUnavailable;
  return v ? yes : no;
}

String fmtCoord(double? v, {required bool isLat}) {
  if (v == null) return kUnavailable;
  final hemi = isLat ? (v >= 0 ? 'N' : 'S') : (v >= 0 ? 'E' : 'W');
  return '${v.abs().toStringAsFixed(6)}° $hemi';
}

String fmtDuration(int? ms) {
  if (ms == null) return kUnavailable;
  if (ms < 1000) return '$ms ms';
  return '${(ms / 1000).toStringAsFixed(1)} s';
}

String fmtClock(int? epochMs) {
  if (epochMs == null) return kUnavailable;
  final t = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// First address of [v] and "(+n)" when there are more; `null` for an empty list.
String? fmtFirstOfMany(List<String> v) =>
    v.isEmpty ? null : (v.length == 1 ? v.first : '${v.first}  (+${v.length - 1})');

String fmtList(List<int> v) => v.isEmpty ? kUnavailable : v.join(', ');
