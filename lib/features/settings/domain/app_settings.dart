import 'dart:convert';

import 'package:flutter/material.dart';

/// User preferences persisted by the platform layer.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.languageCode = 'system',
    this.updateIntervalMs = 1000,
    this.historySeconds = 300,
    this.recordHistory = true,
    this.customLatencyTargets = const [],
  });

  static const List<int> updateIntervalOptionsMs = [500, 1000, 2000, 5000];
  static const List<int> historyOptionsSeconds = [60, 300];

  final ThemeMode themeMode;

  /// `system`, `zh` or `en`.
  final String languageCode;

  /// Minimum interval between samples that reach the UI and history.
  final int updateIntervalMs;

  /// Chart window / retention: 60 s or 300 s.
  final int historySeconds;

  /// When false, no samples are retained (charts stay empty, export is empty).
  final bool recordHistory;

  /// User-added latency test targets as `host:port` strings.
  final List<String> customLatencyTargets;

  Locale? get locale {
    switch (languageCode) {
      case 'zh':
        return const Locale('zh');
      case 'en':
        return const Locale('en');
      default:
        return null;
    }
  }

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? languageCode,
    int? updateIntervalMs,
    int? historySeconds,
    bool? recordHistory,
    List<String>? customLatencyTargets,
  }) =>
      AppSettings(
        customLatencyTargets: customLatencyTargets ?? this.customLatencyTargets,
        themeMode: themeMode ?? this.themeMode,
        languageCode: languageCode ?? this.languageCode,
        updateIntervalMs: updateIntervalMs ?? this.updateIntervalMs,
        historySeconds: historySeconds ?? this.historySeconds,
        recordHistory: recordHistory ?? this.recordHistory,
      );

  String toJson() => jsonEncode({
        'themeMode': themeMode.name,
        'languageCode': languageCode,
        'updateIntervalMs': updateIntervalMs,
        'historySeconds': historySeconds,
        'recordHistory': recordHistory,
        'customLatencyTargets': customLatencyTargets,
      });

  factory AppSettings.fromJson(String? source) {
    if (source == null || source.isEmpty) return const AppSettings();
    try {
      final m = jsonDecode(source);
      if (m is! Map) return const AppSettings();
      final mode = ThemeMode.values.firstWhere(
        (e) => e.name == m['themeMode'],
        orElse: () => ThemeMode.dark,
      );
      final interval = m['updateIntervalMs'];
      final history = m['historySeconds'];
      return AppSettings(
        themeMode: mode,
        languageCode: const ['system', 'zh', 'en'].contains(m['languageCode'])
            ? m['languageCode'] as String
            : 'system',
        updateIntervalMs: updateIntervalOptionsMs.contains(interval) ? interval as int : 1000,
        historySeconds: historyOptionsSeconds.contains(history) ? history as int : 300,
        recordHistory: m['recordHistory'] is bool ? m['recordHistory'] as bool : true,
        customLatencyTargets: m['customLatencyTargets'] is List
            ? [
                for (final e in m['customLatencyTargets'] as List)
                  if (e is String && e.isNotEmpty) e,
              ].take(20).toList()
            : const [],
      );
    } on Object {
      return const AppSettings();
    }
  }
}
