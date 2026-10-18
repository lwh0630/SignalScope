import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/signal_quality.dart';
import '../../../data/models/gnss_info.dart';
import 'constellation_flag.dart';
import 'sky_plot.dart';

/// Sorts satellites by constellation, then SVID, so bars keep their position
/// between updates instead of jumping around with the signal strength.
List<SatelliteInfo> sortForDisplay(List<SatelliteInfo> input) {
  final list = [...input];
  list.sort((a, b) {
    final c = a.constellation.code.compareTo(b.constellation.code);
    return c != 0 ? c : a.svid.compareTo(b.svid);
  });
  return list;
}

/// Satellites grouped by constellation, each group sorted by SVID.
List<List<SatelliteInfo>> groupByConstellation(List<SatelliteInfo> input) {
  final groups = <List<SatelliteInfo>>[];
  for (final s in sortForDisplay(input)) {
    if (groups.isNotEmpty && groups.last.first.constellation == s.constellation) {
      groups.last.add(s);
    } else {
      groups.add([s]);
    }
  }
  return groups;
}

/// Geometry shared by the painter and hit testing.
class Cn0Layout {
  Cn0Layout(List<List<SatelliteInfo>> groups) {
    var x = padX;
    for (var g = 0; g < groups.length; g++) {
      if (g > 0) x += groupGap;
      final start = x;
      for (final s in groups[g]) {
        slots.add(Cn0Slot(s, g, x));
        x += slot;
      }
      spans.add((start, x - (slot - barW)));
    }
    contentWidth = x - (slot - barW) + padX;
    if (groups.isEmpty) contentWidth = 0;
  }

  static const double barW = 16;
  static const double slot = 26;
  static const double groupGap = 16;
  static const double padX = 6;
  static const double headerH = 26;
  static const double topPad = 16;
  static const double plotH = 130;
  static const double footerH = 24;
  static const double maxCn0 = 60;
  static const double totalHeight = headerH + topPad + plotH + footerH;
  static const double plotTop = headerH + topPad;
  static const double plotBottom = plotTop + plotH;

  final List<Cn0Slot> slots = [];

  /// Horizontal extent (left, right) of each constellation group.
  final List<(double, double)> spans = [];
  late final double contentWidth;

  static double yOf(double cn0) => plotBottom - (cn0.clamp(0, maxCn0) / maxCn0) * plotH;

  /// Index of the bar at [x], or -1. Taps in the gap snap to the nearest bar.
  int slotAt(double x) {
    var best = -1;
    var bestDist = double.infinity;
    for (var i = 0; i < slots.length; i++) {
      final c = slots[i].left + barW / 2;
      final d = (x - c).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return bestDist <= slot / 2 + 2 ? best : -1;
  }
}

class Cn0Slot {
  const Cn0Slot(this.sat, this.group, this.left);

  final SatelliteInfo sat;
  final int group;
  final double left;
}

/// C/N0 per satellite: rounded gradient bars grouped by constellation (with
/// the operator's flag), a fixed dB-Hz axis, reference lines, the mean line of
/// tracked satellites and tap-for-details. Bars of satellites used in the fix
/// are solid with a bright outline, the others are translucent; a satellite
/// that is not tracked (C/N0 = 0 or missing) only gets a thin grey stub.
class Cn0Bars extends StatefulWidget {
  const Cn0Bars({super.key, required this.satellites});

  final List<SatelliteInfo> satellites;

  @override
  State<Cn0Bars> createState() => _Cn0BarsState();
}

class _Cn0BarsState extends State<Cn0Bars> {
  String? _selectedKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = groupByConstellation(widget.satellites);
    final layout = Cn0Layout(groups);
    final avg = _mean(widget.satellites);
    SatelliteInfo? selected;
    for (final s in widget.satellites) {
      if (s.key == _selectedKey) selected = s;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: Cn0Layout.totalHeight,
          child: Row(
            children: [
              CustomPaint(
                size: const Size(30, Cn0Layout.totalHeight),
                painter: _AxisPainter(textColor: theme.colorScheme.onSurfaceVariant),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final width = math.max(layout.contentWidth, box.maxWidth);
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) {
                          final i = layout.slotAt(d.localPosition.dx);
                          setState(() {
                            final key = i < 0 ? null : layout.slots[i].sat.key;
                            _selectedKey = key == _selectedKey ? null : key;
                          });
                        },
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          builder: (context, grow, _) => CustomPaint(
                            size: Size(width, Cn0Layout.totalHeight),
                            painter: _BarsPainter(
                              layout: layout,
                              groups: groups,
                              average: avg,
                              selectedKey: _selectedKey,
                              grow: grow,
                              gridColor: theme.colorScheme.outlineVariant,
                              textColor: theme.colorScheme.onSurfaceVariant,
                              labelColor: theme.colorScheme.onSurface,
                              surfaceColor: theme.colorScheme.surfaceContainerHigh,
                              averageLabel: context.tr('gnss.cn0.avg'),
                              groupLabel: (c) => c.label,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        if (avg != null) ...[
          const SizedBox(height: 6),
          // The mean line is explained here instead of inside the plot, where a
          // label would sit on top of the bar values.
          Row(
            children: [
              const SizedBox(width: 30),
              CustomPaint(
                size: const Size(22, 2),
                painter: _DashSwatchPainter(color: SignalQuality.cn0(avg).color),
              ),
              const SizedBox(width: 8),
              Text(
                '${context.tr('gnss.cn0.avg')} ${avg.toStringAsFixed(1)} dB-Hz',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: SignalQuality.cn0(avg).color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: selected == null
              ? Text(
                  context.tr('gnss.cn0.tapHint'),
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                )
              : _SatDetail(sat: selected),
        ),
      ],
    );
  }

  static double? _mean(List<SatelliteInfo> sats) {
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
}

class _SatDetail extends StatelessWidget {
  const _SatDetail({required this.sat});

  final SatelliteInfo sat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flag = ConstellationFlag.of(sat.constellation);
    final color = constellationColor(sat.constellation);
    final tracked = (sat.cn0DbHz ?? 0) > 0;
    final rows = <(String, String)>[
      (context.tr('gnss.col.az'), fmtNum(sat.azimuthDeg, unit: '°')),
      (context.tr('gnss.col.el'), fmtNum(sat.elevationDeg, unit: '°')),
      ('C/N0', tracked ? fmtNum(sat.cn0DbHz, unit: 'dB-Hz', decimals: 1) : kUnavailable),
      (
        context.tr('gnss.used'),
        fmtBool(sat.usedInFix, yes: context.tr('common.yes'), no: context.tr('common.no')),
      ),
      if (sat.carrierFrequencyHz != null)
        (context.tr('gnss.carrier'), '${(sat.carrierFrequencyHz! / 1e6).toStringAsFixed(2)} MHz'),
      if (sat.basebandCn0DbHz != null) (context.tr('gnss.baseband'), fmtNum(sat.basebandCn0DbHz, unit: 'dB-Hz', decimals: 1)),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${flag.emoji}  ${sat.constellation.label} ${sat.svid}',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            context.tr(flag.countryKey),
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      r.$1,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  Text(r.$2, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

void _text(
  Canvas canvas,
  String s,
  Offset anchor,
  Color color,
  double size, {
  bool bold = false,
  bool alignRight = false,
  bool alignLeft = false,
  double? maxWidth,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(maxWidth: maxWidth ?? double.infinity);
  final dx = alignRight ? anchor.dx - tp.width : (alignLeft ? anchor.dx : anchor.dx - tp.width / 2);
  tp.paint(canvas, Offset(dx, anchor.dy - tp.height / 2));
}

void _dashed(Canvas canvas, Offset a, Offset b, Paint paint, {double dash = 4, double gap = 4}) {
  final total = (b - a).distance;
  if (total == 0) return;
  final dir = (b - a) / total;
  var d = 0.0;
  while (d < total) {
    canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, total), paint);
    d += dash + gap;
  }
}

class _DashSwatchPainter extends CustomPainter {
  _DashSwatchPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    _dashed(
      canvas,
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = color
        ..strokeWidth = 2,
      dash: 6,
      gap: 3,
    );
  }

  @override
  bool shouldRepaint(_DashSwatchPainter old) => old.color != color;
}

class _AxisPainter extends CustomPainter {
  _AxisPainter({required this.textColor});

  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final v in const [0.0, 15.0, 30.0, 45.0, 60.0]) {
      _text(canvas, '${v.round()}', Offset(size.width - 6, Cn0Layout.yOf(v)), textColor, 10, alignRight: true);
    }
    _text(canvas, 'dB-Hz', Offset(size.width - 6, Cn0Layout.plotTop - 14), textColor.withValues(alpha: 0.7), 9,
        alignRight: true);
  }

  @override
  bool shouldRepaint(_AxisPainter old) => old.textColor != textColor;
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.layout,
    required this.groups,
    required this.average,
    required this.selectedKey,
    required this.grow,
    required this.gridColor,
    required this.textColor,
    required this.labelColor,
    required this.surfaceColor,
    required this.averageLabel,
    required this.groupLabel,
  });

  final Cn0Layout layout;
  final List<List<SatelliteInfo>> groups;
  final double? average;
  final String? selectedKey;
  final double grow;
  final Color gridColor;
  final Color textColor;
  final Color labelColor;
  final Color surfaceColor;
  final String averageLabel;
  final String Function(Constellation) groupLabel;

  @override
  void paint(Canvas canvas, Size size) {
    final left = 0.0;
    final right = size.width;

    // Reference lines.
    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    for (final v in const [0.0, 15.0, 30.0, 45.0, 60.0]) {
      final y = Cn0Layout.yOf(v);
      if (v == 0) {
        canvas.drawLine(Offset(left, y), Offset(right, y), grid..color = gridColor);
        grid.color = gridColor.withValues(alpha: 0.4);
      } else {
        _dashed(canvas, Offset(left, y), Offset(right, y), grid);
      }
    }

    // Group headers: flag + name over a coloured underline, separators between groups.
    for (var g = 0; g < groups.length; g++) {
      final (gl, gr) = layout.spans[g];
      final c = groups[g].first.constellation;
      final color = constellationColor(c);
      final flag = ConstellationFlag.of(c);
      const labelY = Cn0Layout.headerH - 12;
      final span = gr - gl;
      final full = '${flag.emoji} ${groupLabel(c)}';
      // Show the name only when the group is wide enough, the flag always.
      final text = span >= 70 ? full : flag.emoji;
      _text(canvas, text, Offset((gl + gr) / 2, labelY), color, 11, bold: true, maxWidth: span + 24);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(gl, Cn0Layout.headerH - 3, gr, Cn0Layout.headerH), const Radius.circular(2)),
        Paint()..color = color.withValues(alpha: 0.85),
      );
      if (g > 0) {
        final x = gl - Cn0Layout.groupGap / 2;
        _dashed(
          canvas,
          Offset(x, Cn0Layout.headerH + 4),
          Offset(x, Cn0Layout.plotBottom + Cn0Layout.footerH - 4),
          Paint()
            ..color = gridColor.withValues(alpha: 0.35)
            ..strokeWidth = 1,
          dash: 2,
          gap: 4,
        );
      }
    }

    // Bars.
    for (final slot in layout.slots) {
      _drawBar(canvas, slot);
    }

    // Mean line of tracked satellites (derived value).
    final avg = average;
    if (avg != null) {
      final y = Cn0Layout.yOf(avg);
      final avgColor = SignalQuality.cn0(avg).color;
      _dashed(
        canvas,
        Offset(left, y),
        Offset(right, y),
        Paint()
          ..color = avgColor.withValues(alpha: 0.9)
          ..strokeWidth = 1.4,
        dash: 6,
        gap: 3,
      );
    }
  }

  void _drawBar(Canvas canvas, Cn0Slot slot) {
    final s = slot.sat;
    final cn0 = s.cn0DbHz;
    final tracked = cn0 != null && cn0 > 0;
    final used = s.usedInFix == true;
    final selected = s.key == selectedKey;
    final dim = selectedKey != null && !selected;
    final k = dim ? 0.35 : 1.0;
    final x = slot.left;
    const w = Cn0Layout.barW;

    // Track.
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, Cn0Layout.plotTop, w, Cn0Layout.plotH),
      const Radius.circular(8),
    );
    canvas.drawRRect(track, Paint()..color = gridColor.withValues(alpha: 0.14 * k));

    if (tracked) {
      final color = SignalQuality.cn0(cn0).color;
      final top = Cn0Layout.yOf(cn0 * grow);
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTRB(x, top, x + w, Cn0Layout.plotBottom),
        topLeft: const Radius.circular(8),
        topRight: const Radius.circular(8),
        bottomLeft: const Radius.circular(3),
        bottomRight: const Radius.circular(3),
      );
      if (selected) {
        canvas.drawRRect(
          rect,
          Paint()
            ..color = color.withValues(alpha: 0.6)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, top),
            Offset(0, Cn0Layout.plotBottom),
            [
              color.withValues(alpha: (used ? 1.0 : 0.6) * k),
              color.withValues(alpha: (used ? 0.45 : 0.18) * k),
            ],
          ),
      );
      if (used) {
        canvas.drawRRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = Colors.white.withValues(alpha: 0.85 * k),
        );
      } else {
        canvas.drawRRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = color.withValues(alpha: 0.55 * k),
        );
      }
      _text(canvas, cn0.round().toString(), Offset(x + w / 2, top - 8), color.withValues(alpha: k), 10, bold: true);
    } else {
      // Not tracked: a thin grey stub, never a fake value.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 3, Cn0Layout.plotBottom - 3, w - 6, 3),
          const Radius.circular(2),
        ),
        Paint()..color = textColor.withValues(alpha: 0.5 * k),
      );
      _text(canvas, kUnavailable, Offset(x + w / 2, Cn0Layout.plotBottom - 11), textColor.withValues(alpha: k), 9);
    }

    // SVID + used-in-fix marker.
    _text(canvas, '${s.svid}', Offset(x + w / 2, Cn0Layout.plotBottom + 9), labelColor.withValues(alpha: k), 10,
        bold: used || selected);
    final dotColor = constellationColor(s.constellation);
    canvas.drawCircle(
      Offset(x + w / 2, Cn0Layout.plotBottom + 19),
      used ? 3 : 2.2,
      used
          ? (Paint()..color = dotColor.withValues(alpha: k))
          : (Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = dotColor.withValues(alpha: 0.7 * k)),
    );
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.layout != layout ||
      old.average != average ||
      old.selectedKey != selectedKey ||
      old.grow != grow ||
      old.gridColor != gridColor ||
      old.textColor != textColor ||
      old.labelColor != labelColor ||
      old.surfaceColor != surfaceColor ||
      old.averageLabel != averageLabel;
}
