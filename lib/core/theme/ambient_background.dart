import 'package:flutter/material.dart';

import 'background.dart';
import 'glass_tokens.dart';

/// The bottom-most layer of the app: a calm base colour with three large, soft
/// light blobs (one of the [BackgroundStyle] presets), or a picture the user
/// picked with a veil over it. They give the glass surfaces above something to
/// blur and refract.
///
/// The background is static on purpose: SignalScope is left open for long
/// sessions and its pages repaint with live sensor data, so a drifting
/// background would re-blur every glass surface on top of it for no benefit.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({
    super.key,
    this.style = BackgroundStyle.aurora,
    this.image,
    this.dim = 0.45,
    this.child,
  });

  /// Gradient preset, or [BackgroundStyle.image] together with [image].
  final BackgroundStyle style;

  /// Picture for [BackgroundStyle.image]; without it the default glow shows.
  final ImageProvider? image;

  /// Strength (0..0.85) of the theme-coloured veil laid over the picture so the
  /// glass text stays readable.
  final double dim;

  final Widget? child;

  bool get _showsImage => style == BackgroundStyle.image && image != null;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final palette = BackgroundPalette.of(style, g);
    final glow = CustomPaint(
      painter: _AmbientPainter(palette, g.isDark),
      size: Size.infinite,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        // Own layer: the background never repaints with the page above it.
        RepaintBoundary(
          child: _showsImage
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: palette.base),
                    Image(
                      image: image!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      // A missing / unreadable file falls back to the glow.
                      errorBuilder: (_, _, _) => glow,
                    ),
                    ColoredBox(
                      color: (g.isDark ? Colors.black : Colors.white)
                          .withValues(alpha: dim.clamp(0.0, 0.85)),
                    ),
                  ],
                )
              : glow,
        ),
        child ?? const SizedBox.shrink(),
      ],
    );
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.palette, this.isDark);

  final BackgroundPalette palette;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.base);
    if (size.isEmpty) return;
    final reach = size.longestSide;
    final strength = isDark ? 0.5 : 0.55;

    void blob(Color color, double x, double y, double radius) {
      final center = Offset(size.width * x, size.height * y);
      final r = reach * radius;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: strength),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }

    blob(palette.a, 0.1, 0.06, 0.6);
    blob(palette.b, 0.95, 0.34, 0.52);
    blob(palette.c, 0.45, 1.04, 0.6);
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      old.palette != palette || old.isDark != isDark;
}
