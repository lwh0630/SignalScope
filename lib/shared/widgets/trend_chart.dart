import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/history.dart';
import '../../core/i18n/strings.dart';
import '../../core/providers.dart';
import '../../data/models/signal_history_point.dart';
import 'cards.dart';

/// Describes one line of a [TrendCard].
class TrendSeries {
  const TrendSeries({
    required this.key,
    required this.label,
    required this.unit,
    required this.color,
  });

  /// History series key (see `HistoryNotifier`).
  final String key;
  final String label;
  final String unit;
  final Color color;
}

/// Card with a live line chart and a 60 s / 5 min window switch.
///
/// Reads from the bounded history store; it never produces samples itself.
class TrendCard extends ConsumerStatefulWidget {
  const TrendCard({
    super.key,
    required this.title,
    required this.series,
    this.minY,
    this.maxY,
  });

  final String title;
  final List<TrendSeries> series;

  /// Preferred axis range; widened automatically if data falls outside.
  final double? minY;
  final double? maxY;

  @override
  ConsumerState<TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends ConsumerState<TrendCard> {
  int? _windowSeconds;

  @override
  Widget build(BuildContext context) {
    final int window = _windowSeconds ?? ref.watch(settingsProvider.select((s) => s.historySeconds));
    final data = <List<SignalHistoryPoint>>[
      for (final s in widget.series) ref.watch(historySeriesProvider(s.key)),
    ];
    final theme = Theme.of(context);

    var newest = 0;
    for (final list in data) {
      if (list.isNotEmpty) newest = math.max(newest, list.last.timestampMs);
    }
    final hasData = newest > 0;

    final lines = <LineChartBarData>[];
    var lo = double.infinity;
    var hi = -double.infinity;
    for (var i = 0; i < data.length; i++) {
      final spots = <FlSpot>[];
      for (final p in data[i]) {
        final x = (p.timestampMs - newest) / 1000.0;
        if (x < -window) continue;
        spots.add(FlSpot(x, p.value));
        lo = math.min(lo, p.value);
        hi = math.max(hi, p.value);
      }
      lines.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.15,
          preventCurveOverShooting: true,
          barWidth: 2.4,
          color: widget.series[i].color,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: i == 0,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                widget.series[i].color.withValues(alpha: 0.25),
                widget.series[i].color.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      );
    }

    double minY;
    double maxY;
    if (!hasData || lo == double.infinity) {
      minY = widget.minY ?? 0;
      maxY = widget.maxY ?? 100;
    } else {
      minY = widget.minY == null ? lo - 5 : math.min(widget.minY!, lo - 2);
      maxY = widget.maxY == null ? hi + 5 : math.max(widget.maxY!, hi + 2);
    }
    if (maxY - minY < 10) {
      maxY = minY + 10;
    }

    return SectionCard(
      title: widget.title,
      trailing: SegmentedButton<int>(
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        segments: [
          ButtonSegment(value: 60, label: Text(context.tr('common.last60s'))),
          ButtonSegment(value: 300, label: Text(context.tr('common.last5min'))),
        ],
        selected: {window},
        onSelectionChanged: (s) => setState(() => _windowSeconds = s.first),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              for (var i = 0; i < widget.series.length; i++)
                _LegendItem(
                  color: widget.series[i].color,
                  label: widget.series[i].label,
                  value: data[i].isEmpty
                      ? '--'
                      : '${data[i].last.value.round()} ${widget.series[i].unit}',
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 170,
            child: hasData
                ? RepaintBoundary(
                    child: LineChart(
                      LineChartData(
                        minX: -window.toDouble(),
                        maxX: 0,
                        minY: minY,
                        maxY: maxY,
                        clipData: const FlClipData.all(),
                        lineBarsData: lines,
                        borderData: FlBorderData(show: false),
                        gridData: FlGridData(
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (_) => FlLine(
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                            strokeWidth: 1,
                          ),
                        ),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(),
                          rightTitles: const AxisTitles(),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                if (value == meta.min || value == meta.max) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  value.round().toString(),
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 22,
                              interval: window / 4,
                              getTitlesWidget: (value, meta) {
                                final s = value.round();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    s == 0 ? '0' : '${s}s',
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      duration: const Duration(milliseconds: 250),
                    ),
                  )
                : Center(
                    child: Text(
                      context.tr('common.noData'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label, required this.value});

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.labelMedium),
        const SizedBox(width: 6),
        Text(
          value,
          style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
