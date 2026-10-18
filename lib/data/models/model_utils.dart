/// Helpers shared by model `fromMap` constructors.
///
/// Native code sends `null` for any value the system did not report. These
/// helpers never turn a missing value into 0.
library;

int? asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return null;
}

double? asDouble(Object? v) => v is num ? v.toDouble() : null;

bool? asBool(Object? v) => v is bool ? v : null;

String? asString(Object? v) {
  if (v is String && v.isNotEmpty) return v;
  return null;
}

List<int> asIntList(Object? v) {
  if (v is List) {
    return v.whereType<num>().map((e) => e.toInt()).toList(growable: false);
  }
  return const <int>[];
}

List<String> asStringList(Object? v) {
  if (v is List) {
    return v.whereType<String>().toList(growable: false);
  }
  return const <String>[];
}

List<Map<Object?, Object?>> asMapList(Object? v) {
  if (v is List) {
    return v.whereType<Map>().map((e) => e.cast<Object?, Object?>()).toList();
  }
  return const [];
}

Map<Object?, Object?> asMap(Object? v) {
  if (v is Map) return v.cast<Object?, Object?>();
  return const {};
}
