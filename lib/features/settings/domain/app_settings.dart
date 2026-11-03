import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/theme/background.dart';

/// User preferences persisted by the platform layer.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.languageCode = 'system',
    this.updateIntervalMs = 1000,
    this.historySeconds = 300,
    this.recordHistory = true,
    this.customLatencyTargets = const [],
    this.autoCheckUpdates = true,
    this.lastUpdateCheckMs,
    this.background = BackgroundStyle.aurora,
    this.backgroundImage = '',
    this.backgroundDim = defaultBackgroundDim,
  });

  static const double defaultBackgroundDim = 0.45;
  static const double maxBackgroundDim = 0.85;

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

  /// Check GitHub Releases for a newer version at most once per day at launch.
  final bool autoCheckUpdates;

  /// Epoch ms of the last successful update check; `null` if never.
  final int? lastUpdateCheckMs;

  /// Gradient preset under the glass, or [BackgroundStyle.image].
  final BackgroundStyle background;

  /// App-private path of the picture used by [BackgroundStyle.image]; empty when
  /// there is none.
  final String backgroundImage;

  /// Strength (0 to [maxBackgroundDim]) of the veil over the picture.
  final double backgroundDim;

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
    bool? autoCheckUpdates,
    int? lastUpdateCheckMs,
    BackgroundStyle? background,
    String? backgroundImage,
    double? backgroundDim,
  }) => AppSettings(
    background: background ?? this.background,
    backgroundImage: backgroundImage ?? this.backgroundImage,
    backgroundDim: backgroundDim ?? this.backgroundDim,
    customLatencyTargets: customLatencyTargets ?? this.customLatencyTargets,
    autoCheckUpdates: autoCheckUpdates ?? this.autoCheckUpdates,
    lastUpdateCheckMs: lastUpdateCheckMs ?? this.lastUpdateCheckMs,
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
    'autoCheckUpdates': autoCheckUpdates,
    'lastUpdateCheckMs': lastUpdateCheckMs,
    'background': background.name,
    'backgroundImage': backgroundImage,
    'backgroundDim': backgroundDim,
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
      final image = m['backgroundImage'] is String
          ? m['backgroundImage'] as String
          : '';
      var style = BackgroundStyle.fromName(m['background']);
      // A picture style without a picture falls back to the default glow.
      if (style == BackgroundStyle.image && image.isEmpty) {
        style = BackgroundStyle.aurora;
      }
      final dim = m['backgroundDim'];
      return AppSettings(
        background: style,
        backgroundImage: image,
        backgroundDim: dim is num && dim.isFinite
            ? dim.toDouble().clamp(0.0, maxBackgroundDim)
            : defaultBackgroundDim,
        themeMode: mode,
        languageCode: const ['system', 'zh', 'en'].contains(m['languageCode'])
            ? m['languageCode'] as String
            : 'system',
        updateIntervalMs: updateIntervalOptionsMs.contains(interval)
            ? interval as int
            : 1000,
        historySeconds: historyOptionsSeconds.contains(history)
            ? history as int
            : 300,
        recordHistory: m['recordHistory'] is bool
            ? m['recordHistory'] as bool
            : true,
        customLatencyTargets: m['customLatencyTargets'] is List
            ? [
                for (final e in m['customLatencyTargets'] as List)
                  if (e is String && e.isNotEmpty) e,
              ].take(20).toList()
            : const [],
        autoCheckUpdates: m['autoCheckUpdates'] is bool
            ? m['autoCheckUpdates'] as bool
            : true,
        lastUpdateCheckMs: m['lastUpdateCheckMs'] is int
            ? m['lastUpdateCheckMs'] as int
            : null,
      );
    } on Object {
      return const AppSettings();
    }
  }
}
