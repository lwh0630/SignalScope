import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/wifi_utils.dart';
import '../../../data/models/wifi_info.dart';
import 'channel_geometry.dart';

/// Stable colour of an access point (derived from its BSSID).
const List<Color> kChannelPalette = [
  Color(0xFF29C5F6),
  Color(0xFFB388FF),
  Color(0xFFFFB74D),
  Color(0xFF69F0AE),
  Color(0xFFFF8A80),
  Color(0xFFFFEE58),
  Color(0xFF4DD0E1),
  Color(0xFFF48FB1),
  Color(0xFFAED581),
  Color(0xFF9FA8DA),
];

Color channelColorOf(String bssid) =>
    kChannelPalette[(bssid.toLowerCase().hashCode & 0x7fffffff) % kChannelPalette.length];

/// Channel occupancy graph.
///
/// Every access point is a smooth bell centred on its centre frequency whose
/// width is the channel width and whose height is its RSSI. Tap a curve or a
/// legend chip to highlight an access point and read its details.
class ChannelGraph extends StatefulWidget {
  const ChannelGraph({
    super.key,
    required this.aps,
    required this.band,
    this.connectedBssid,
  });

  final List<WifiScanInfo> aps;
  final WifiBand band;
  final String? connectedBssid;

  @override
  State<ChannelGraph> createState() => _ChannelGraphState();
}

class _ChannelGraphState extends State<ChannelGraph> {
  String? _selected;

  @override
  void didUpdateWidget(ChannelGraph old) {
    super.didUpdateWidget(old);
    if (old.band != widget.band) _selected = null;
  }

  void _toggle(String? bssid) => setState(() => _selected = bssid == _selected ? null : bssid);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inBand = ChannelGeometry.inBand(widget.aps, widget.band);
    final connected = widget.connectedBssid?.toLowerCase();
    WifiScanInfo? selected;
    for (final a in inBand) {
      if (a.bssid == _selected) selected = a;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1.75,
          child: LayoutBuilder(
            builder: (context, box) {
              final size = Size(box.maxWidth, box.maxHeight);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => setState(() {
                  final hit = ChannelPainter.apAt(d.localPosition, size, inBand, widget.band);
                  _selected = hit == _selected ? null : hit;
                }),
                child: Stack(
                  children: [
                    TweenAnimationBuilder<double>(
                      key: ValueKey(widget.band),
                      tween: Tween<double>(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                      builder: (context, grow, _) => RepaintBoundary(
                        child: CustomPaint(
                          size: size,
                          painter: ChannelPainter(
                            aps: inBand,
                            band: widget.band,
                            connectedBssid: connected,
                            selectedBssid: selected?.bssid,
                            grow: grow,
                            gridColor: theme.colorScheme.outlineVariant,
                            textColor: theme.colorScheme.onSurfaceVariant,
                            surfaceColor: theme.colorScheme.surfaceContainerHigh,
                          ),
                        ),
                      ),
                    ),
                    if (inBand.isEmpty)
                      Center(
                        child: Text(
                          context.tr('wifi.chart.empty'),
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        if (inBand.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final ap in inBand.take(12))
                _LegendChip(
                  ap: ap,
                  selected: ap.bssid == selected?.bssid,
                  connected: connected != null && ap.bssid.toLowerCase() == connected,
                  onTap: () => _toggle(ap.bssid),
                ),
              if (inBand.length > 12)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Text('+${inBand.length - 12}', style: theme.textTheme.labelMedium),
                ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: selected == null
                ? Text(
                    context.tr('wifi.chart.tapHint'),
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  )
                : _DetailCard(
                    ap: selected,
                    connected: connected != null && selected.bssid.toLowerCase() == connected,
                  ),
          ),
        ],
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.ap, required this.selected, required this.connected, required this.onTap});

  final WifiScanInfo ap;
  final bool selected;
  final bool connected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = channelColorOf(ap.bssid);
    final name = ap.ssid ?? context.tr('wifi.hiddenSsid');
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: selected ? 0.28 : 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: selected ? 1 : 0.45), width: selected ? 1.6 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'CH${ap.channel ?? '--'} · ${fmtNum(ap.rssi)}',
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (connected) ...[
              const SizedBox(width: 4),
              Icon(Icons.check_circle_rounded, size: 13, color: color),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.ap, required this.connected});

  final WifiScanInfo ap;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = channelColorOf(ap.bssid);
    final span = ChannelGeometry.span(ap);
    final lines = <(String, String)>[
      ('BSSID', ap.bssid),
      (context.tr('wifi.channel'), fmtNum(ap.channel)),
      (context.tr('wifi.frequency'), fmtNum(ap.frequencyMhz, unit: 'MHz')),
      (context.tr('wifi.bandwidth'), ap.channelWidthMhz == null ? kUnavailable : '${ap.channelWidthMhz} MHz'),
      if (span != null) (context.tr('wifi.chart.span'), '${span.$1.round()}–${span.$2.round()} MHz'),
      ('RSSI', fmtNum(ap.rssi, unit: 'dBm')),
      (context.tr('wifi.security'), fmtText(ap.securityLabel)),
      (context.tr('wifi.standard'), fmtText(ap.standardLabel)),
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
          Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ap.ssid ?? context.tr('wifi.hiddenSsid'),
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (connected)
                Text(
                  context.tr('wifi.chart.connected'),
                  style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.$1,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  Text(l.$2, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Paints the grid, the bells and their labels. See [ChannelGeometry] for the maths.
class ChannelPainter extends CustomPainter {
  ChannelPainter({
    required this.aps,
    required this.band,
    required this.connectedBssid,
    required this.selectedBssid,
    required this.grow,
    required this.gridColor,
    required this.textColor,
    required this.surfaceColor,
  });

  /// Access points of [band], strongest first.
  final List<WifiScanInfo> aps;
  final WifiBand band;
  final String? connectedBssid;
  final String? selectedBssid;

  /// 0..1 entrance animation progress.
  final double grow;
  final Color gridColor;
  final Color textColor;
  final Color surfaceColor;

  static const double _left = 34;
  static const double _right = 8;
  static const double _top = 16;
  static const double _bottom = 26;
  static const int _samples = 48;

  static Rect plotRect(Size size) =>
      Rect.fromLTRB(_left, _top, size.width - _right, size.height - _bottom);

  /// The access point drawn under [pos], or `null`.
  static String? apAt(Offset pos, Size size, List<WifiScanInfo> aps, WifiBand band) {
    final plot = plotRect(size);
    String? best;
    var bestDist = double.infinity;
    for (final ap in aps) {
      final span = ChannelGeometry.span(ap);
      if (span == null) continue;
      final l = plot.left + ChannelGeometry.xFraction(band, span.$1) * plot.width;
      final r = plot.left + ChannelGeometry.xFraction(band, span.$2) * plot.width;
      if (pos.dx < l || pos.dx > r || pos.dy > plot.bottom + 4) continue;
      final t = (pos.dx - l) / (r - l) * 2 - 1;
      final h = ChannelGeometry.yFraction(ap.rssi!) * plot.height;
      final curveY = plot.bottom - ChannelGeometry.bell(t) * h;
      if (pos.dy < curveY - 14) continue; // clearly above the curve
      final d = (pos.dy - curveY).abs();
      if (d < bestDist) {
        bestDist = d;
        best = ap.bssid;
      }
    }
    return best;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plot = plotRect(size);
    double fx(double mhz) => plot.left + ChannelGeometry.xFraction(band, mhz) * plot.width;
    double fy(double rssi) => plot.bottom - ChannelGeometry.yFraction(rssi) * plot.height;

    _drawGrid(canvas, plot, fx, fy);

    // Weak first so strong curves stay readable; connected / selected on top.
    final order = [...aps.reversed];
    order.sort((a, b) {
      int rank(WifiScanInfo x) {
        if (x.bssid == selectedBssid) return 2;
        if (connectedBssid != null && x.bssid.toLowerCase() == connectedBssid) return 1;
        return 0;
      }

      return rank(a).compareTo(rank(b));
    });

    final labelRects = <Rect>[];
    final labelOrder = aps.take(6).map((a) => a.bssid).toSet();
    final pendingLabels = <(WifiScanInfo, Rect)>[];

    for (final ap in order) {
      final span = ChannelGeometry.span(ap);
      if (span == null) continue;
      final l = fx(span.$1);
      final r = fx(span.$2);
      final h = ChannelGeometry.yFraction(ap.rssi!) * plot.height * grow;
      final color = channelColorOf(ap.bssid);
      final isSelected = ap.bssid == selectedBssid;
      final isConnected = connectedBssid != null && ap.bssid.toLowerCase() == connectedBssid;
      final dim = selectedBssid != null && !isSelected;
      final k = dim ? 0.3 : 1.0;

      final curve = Path();
      for (var i = 0; i <= _samples; i++) {
        final u = i / _samples;
        final x = l + (r - l) * u;
        final y = plot.bottom - ChannelGeometry.bell(u * 2 - 1) * h;
        if (i == 0) {
          curve.moveTo(x, y);
        } else {
          curve.lineTo(x, y);
        }
      }
      final fill = Path.from(curve)
        ..lineTo(r, plot.bottom)
        ..lineTo(l, plot.bottom)
        ..close();

      final top = plot.bottom - h;
      canvas.drawPath(
        fill,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, top),
            Offset(0, plot.bottom),
            [
              color.withValues(alpha: (isConnected || isSelected ? 0.62 : 0.42) * k),
              color.withValues(alpha: 0.02 * k),
            ],
          ),
      );

      if (isConnected || isSelected) {
        canvas.drawPath(
          curve,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..strokeJoin = StrokeJoin.round
            ..color = color.withValues(alpha: 0.5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
      canvas.drawPath(
        curve,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isConnected || isSelected ? 2.8 : 1.6
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: (isConnected || isSelected ? 1 : 0.9) * k),
      );

      if (grow > 0.85 && labelOrder.contains(ap.bssid) && !dim) {
        pendingLabels.add((ap, Rect.fromLTWH((l + r) / 2, top, 0, 0)));
      }
    }

    // Labels: strongest first so they win collisions.
    pendingLabels.sort((a, b) => b.$1.rssi!.compareTo(a.$1.rssi!));
    for (final (ap, anchor) in pendingLabels) {
      final name = ap.ssid ?? ap.bssid.substring(ap.bssid.length >= 8 ? ap.bssid.length - 8 : 0);
      final color = channelColorOf(ap.bssid);
      final tp = TextPainter(
        text: TextSpan(
          text: name,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 90);
      final w = tp.width + 10;
      const h = 16.0;
      for (final lift in const [6.0, 24.0, 42.0]) {
        var x = anchor.left - w / 2;
        x = x.clamp(plot.left, plot.right - w).toDouble();
        final y = anchor.top - lift - h + 6;
        if (y < 0) continue;
        final rect = Rect.fromLTWH(x, y, w, h);
        if (labelRects.any((o) => o.inflate(2).overlaps(rect))) continue;
        labelRects.add(rect);
        final rr = RRect.fromRectAndRadius(rect, const Radius.circular(8));
        canvas.drawRRect(rr, Paint()..color = surfaceColor.withValues(alpha: 0.85));
        canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = color.withValues(alpha: 0.6),
        );
        tp.paint(canvas, Offset(rect.left + 5, rect.top + (h - tp.height) / 2));
        break;
      }
    }
  }

  void _drawGrid(Canvas canvas, Rect plot, double Function(double) fx, double Function(double) fy) {
    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    for (final r in const [-90.0, -70.0, -50.0, -30.0]) {
      final y = fy(r);
      _dashed(canvas, Offset(plot.left, y), Offset(plot.right, y), grid);
      _label(canvas, '${r.round()}', Offset(plot.left - 5, y), textColor, 10, alignRight: true);
    }
    _label(canvas, 'dBm', Offset(plot.left - 5, plot.top - 9), textColor.withValues(alpha: 0.7), 9, alignRight: true);

    final axis = Paint()
      ..color = gridColor
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(plot.left, plot.bottom), Offset(plot.right, plot.bottom), axis);

    final faint = Paint()
      ..color = gridColor.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (final ch in ChannelGeometry.labelChannels(band)) {
      final x = fx(ChannelGeometry.channelCenterMhz(band, ch));
      if (x < plot.left || x > plot.right) continue;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), faint);
      canvas.drawLine(Offset(x, plot.bottom), Offset(x, plot.bottom + 4), axis);
      _label(canvas, '$ch', Offset(x, plot.bottom + 14), textColor, 10);
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0;
    const gap = 4.0;
    final total = (b - a).distance;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final end = (d + dash).clamp(0, total).toDouble();
      canvas.drawLine(a + dir * d, a + dir * end, paint);
      d += dash + gap;
    }
  }

  void _label(Canvas canvas, String s, Offset at, Color color, double size, {bool alignRight = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: color, fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = alignRight ? at.dx - tp.width : at.dx - tp.width / 2;
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(ChannelPainter old) =>
      old.aps != aps ||
      old.band != band ||
      old.connectedBssid != connectedBssid ||
      old.selectedBssid != selectedBssid ||
      old.grow != grow ||
      old.gridColor != gridColor ||
      old.textColor != textColor ||
      old.surfaceColor != surfaceColor;
}
