import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/gnss_info.dart';

/// Colour per constellation, shared by the sky plot, the C/N0 bars and the list.
Color constellationColor(Constellation c) {
  switch (c) {
    case Constellation.gps:
      return SignalColors.chartA;
    case Constellation.glonass:
      return const Color(0xFFFF6B7A);
    case Constellation.beidou:
      return SignalColors.chartC;
    case Constellation.galileo:
      return SignalColors.chartB;
    case Constellation.qzss:
      return SignalColors.chartD;
    case Constellation.sbas:
      return const Color(0xFF90A4AE);
    case Constellation.irnss:
      return const Color(0xFF4DD0E1);
    case Constellation.unknown:
      return SignalColors.none;
  }
}

/// Polar view of the satellites: centre = zenith (90°), rim = horizon (0°),
/// top = true north. Azimuth/elevation are exactly what `GnssStatus` reports.
class SkyPlot extends StatelessWidget {
  const SkyPlot({super.key, required this.satellites});

  final List<SatelliteInfo> satellites;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: SkyPlotPainter(
          satellites: satellites,
          gridColor: theme.colorScheme.outlineVariant,
          textColor: theme.colorScheme.onSurfaceVariant,
          labelColor: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

class SkyPlotPainter extends CustomPainter {
  SkyPlotPainter({
    required this.satellites,
    required this.gridColor,
    required this.textColor,
    required this.labelColor,
  });

  final List<SatelliteInfo> satellites;
  final Color gridColor;
  final Color textColor;
  final Color labelColor;

  /// Offset of a satellite from the plot centre, in units of the plot radius (0..1).
  /// Returns `null` when azimuth or elevation is unknown.
  static Offset? unitPosition(SatelliteInfo s) {
    final az = s.azimuthDeg;
    final el = s.elevationDeg;
    if (az == null || el == null) return null;
    final r = ((90 - el.clamp(0, 90)) / 90).toDouble();
    final a = az * math.pi / 180;
    return Offset(r * math.sin(a), -r * math.cos(a));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = side / 2 - 22; // room for the N/E/S/W labels

    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = gridColor.withValues(alpha: 0.7);
    // Elevation rings at 0°, 30° and 60°.
    for (final f in const [1.0, 2 / 3, 1 / 3]) {
      canvas.drawCircle(center, radius * f, grid);
    }
    canvas.drawLine(center.translate(-radius, 0), center.translate(radius, 0), grid);
    canvas.drawLine(center.translate(0, -radius), center.translate(0, radius), grid);

    _text(canvas, 'N', center.translate(0, -radius - 11), textColor, 12, bold: true);
    _text(canvas, 'E', center.translate(radius + 11, 0), textColor, 12);
    _text(canvas, 'S', center.translate(0, radius + 11), textColor, 12);
    _text(canvas, 'W', center.translate(-radius - 11, 0), textColor, 12);
    _text(canvas, '30°', center.translate(0, -radius * 2 / 3 + 8), textColor.withValues(alpha: 0.6), 9);
    _text(canvas, '60°', center.translate(0, -radius / 3 + 8), textColor.withValues(alpha: 0.6), 9);

    for (final s in satellites) {
      final u = unitPosition(s);
      if (u == null) continue;
      final p = center + u * radius;
      final color = constellationColor(s.constellation);
      final tracked = (s.cn0DbHz ?? 0) > 0;
      final used = s.usedInFix == true;
      final alpha = tracked ? 1.0 : 0.35;
      const dot = 9.0;
      if (used) {
        canvas.drawCircle(p, dot, Paint()..color = color.withValues(alpha: alpha));
        _text(canvas, '${s.svid}', p, const Color(0xFF06101C), 9, bold: true);
      } else {
        canvas.drawCircle(
          p,
          dot,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..color = color.withValues(alpha: alpha),
        );
        _text(canvas, '${s.svid}', p, labelColor.withValues(alpha: alpha), 9);
      }
    }
  }

  void _text(Canvas canvas, String text, Offset center, Color color, double size, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(SkyPlotPainter old) =>
      old.satellites != satellites || old.gridColor != gridColor || old.textColor != textColor;
}
