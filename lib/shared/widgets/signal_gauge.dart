import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Large arc gauge. [fraction] is 0..1 (null = no data); the arc animates
/// when the value changes.
class SignalGauge extends StatelessWidget {
  const SignalGauge({
    super.key,
    required this.fraction,
    required this.color,
    required this.valueText,
    required this.unit,
    this.caption,
    this.size = 220,
  });

  final double? fraction;
  final Color color;
  final String valueText;
  final String unit;
  final String? caption;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: size,
      height: size * 0.86,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: fraction ?? 0),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        builder: (context, animated, _) {
          return CustomPaint(
            painter: _GaugePainter(
              fraction: animated,
              hasValue: fraction != null,
              color: color,
              track: theme.colorScheme.surfaceContainerHighest,
            ),
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(top: size * 0.06),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      valueText,
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: fraction == null ? theme.colorScheme.onSurfaceVariant : color,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      unit,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (caption != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        caption!,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.fraction,
    required this.hasValue,
    required this.color,
    required this.track,
  });

  final double fraction;
  final bool hasValue;
  final Color color;
  final Color track;

  static const double _startAngle = 135 * math.pi / 180;
  static const double _sweep = 270 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.075;
    final side = math.min(size.width, size.height / 0.86);
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, side / 2),
      width: side - stroke,
      height: side - stroke,
    );

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, _startAngle, _sweep, false, trackPaint);

    if (hasValue && fraction > 0) {
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 1.6
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawArc(rect, _startAngle, _sweep * fraction, false, glow);

      final valuePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(rect, _startAngle, _sweep * fraction, false, valuePaint);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.track != track ||
      old.hasValue != hasValue;
}
