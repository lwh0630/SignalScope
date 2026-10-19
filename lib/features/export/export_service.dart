import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/demo_mode.dart';
import '../../core/history.dart';
import '../../core/providers.dart';
import '../../data/models/signal_history_point.dart';
import '../cellular/application/cellular_controller.dart';
import '../gnss/application/gnss_controller.dart';
import '../wifi/application/wifi_controller.dart';

enum ExportFormat {
  csv('csv', 'text/csv'),
  json('json', 'application/json');

  const ExportFormat(this.extension, this.mimeType);
  final String extension;
  final String mimeType;
}

enum ExportStatus { saved, empty, failed }

class ExportOutcome {
  const ExportOutcome(this.status, [this.location]);

  final ExportStatus status;

  /// Human readable place where the file was written (when [status] is saved).
  final String? location;
}

/// Serialises the in-memory history. Pure functions, covered by unit tests.
class ExportFormats {
  ExportFormats._();

  static const String csvHeader = 'timestamp_ms,time_iso,series,value,unit';

  /// RFC 4180 style escaping: quote fields containing a comma, quote or line break.
  static String csvField(String v) {
    if (v.contains(',') ||
        v.contains('"') ||
        v.contains('\n') ||
        v.contains('\r')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  static String toCsv(List<SignalHistoryPoint> points) {
    final b = StringBuffer(csvHeader)..write('\r\n');
    for (final p in points) {
      final iso = DateTime.fromMillisecondsSinceEpoch(
        p.timestampMs,
        isUtc: true,
      ).toIso8601String();
      b
        ..write(p.timestampMs)
        ..write(',')
        ..write(iso)
        ..write(',')
        ..write(csvField(p.series))
        ..write(',')
        ..write(p.value)
        ..write(',')
        ..write(csvField(p.unit))
        ..write('\r\n');
    }
    return b.toString();
  }

  static String toJson({
    required List<SignalHistoryPoint> points,
    required Map<String, Object?> latest,
    required String platform,
    required bool demo,
    required int historySeconds,
    required DateTime exportedAt,
    required String appVersion,
  }) {
    final doc = <String, Object?>{
      'app': 'SignalScope',
      'version': appVersion,
      'exportedAtUtc': exportedAt.toUtc().toIso8601String(),
      'platform': platform,
      'dataSource': demo
          ? 'demo (built-in samples, NOT from this device)'
          : 'device',
      'historyWindowSeconds': historySeconds,
      'note': 'Values are exactly as reported by the system. null means the system did not report the value.',
      'latest': latest,
      'sampleCount': points.length,
      'samples': [
        for (final p in points)
          {
            'timestampMs': p.timestampMs,
            'timeUtc': DateTime.fromMillisecondsSinceEpoch(
              p.timestampMs,
              isUtc: true,
            ).toIso8601String(),
            'series': p.series,
            'value': p.value,
            'unit': p.unit,
          },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(doc);
  }

  static String fileName(
    ExportFormat format,
    DateTime now, {
    bool demo = false,
  }) {
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return 'signalscope_${demo ? 'demo_' : ''}$stamp.${format.extension}';
  }
}

/// Exports history through the platform's `saveExport`.
class ExportActions {
  ExportActions(this._ref);

  final Ref _ref;

  Future<ExportOutcome> export(ExportFormat format) async {
    final points = _ref.read(historyProvider.notifier).all();
    if (points.isEmpty) return const ExportOutcome(ExportStatus.empty);

    final platform = _ref.read(signalPlatformProvider);
    final demo = _ref.read(demoModeProvider);
    final now = DateTime.now();
    final appVersion = await _ref.read(installedVersionProvider.future);
    final content = switch (format) {
      ExportFormat.csv => ExportFormats.toCsv(points),
      ExportFormat.json => ExportFormats.toJson(
        points: points,
        latest: _latestSnapshot(),
        platform: platform.name,
        demo: demo,
        historySeconds: _ref.read(settingsProvider).historySeconds,
        exportedAt: now,
        appVersion: appVersion,
      ),
    };
    final where = await platform.saveExport(
      ExportFormats.fileName(format, now, demo: demo),
      format.mimeType,
      content,
    );
    return where == null
        ? const ExportOutcome(ExportStatus.failed)
        : ExportOutcome(ExportStatus.saved, where);
  }

  Map<String, Object?> _latestSnapshot() {
    final cell = _ref.read(cellularControllerProvider);
    final wifi = _ref.read(wifiControllerProvider);
    final gnss = _ref.read(gnssControllerProvider);
    return {
      'sims': [for (final s in cell.sims) s.toMap()],
      'cellular': [for (final e in cell.latest.values) e.toMap()],
      'wifiConnection': wifi.connection?.toMap(),
      'wifiScan': wifi.scan == null
          ? null
          : [for (final r in wifi.scan!.results) r.toMap()],
      'gnss': gnss.snapshot?.toMap(),
    };
  }
}

final exportActionsProvider = Provider<ExportActions>(ExportActions.new);
