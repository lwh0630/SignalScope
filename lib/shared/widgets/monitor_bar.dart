import 'package:flutter/material.dart';

import '../../core/i18n/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../features/monitoring/monitor_status.dart';
import 'cards.dart';

/// Status pill with start / pause / stop controls shared by all monitors.
class MonitorBar extends StatelessWidget {
  const MonitorBar({
    super.key,
    required this.status,
    required this.streaming,
    required this.onStart,
    required this.onPause,
    required this.onStop,
    this.updatedAtMs,
    this.extra,
  });

  final MonitorStatus status;

  /// Native listeners are currently registered.
  final bool streaming;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onStop;
  final int? updatedAtMs;

  /// Optional trailing widget (e.g. a scan button).
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (status) {
      MonitorStatus.listening =>
        streaming
            ? (context.tr('common.listening'), SignalColors.excellent)
            : (context.tr('common.idle'), SignalColors.none),
      MonitorStatus.paused => (context.tr('common.paused'), SignalColors.fair),
      MonitorStatus.stopped => (context.tr('common.stopped'), SignalColors.bad),
    };
    return Row(
      children: [
        StatusPill(text: label, color: color, icon: Icons.sensors_rounded),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            updatedAtMs == null
                ? ''
                : context.tr('common.updatedAt', [fmtClock(updatedAtMs)]),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ?extra,
        if (status == MonitorStatus.listening)
          IconButton(
            tooltip: context.tr('common.pause'),
            onPressed: onPause,
            icon: const Icon(Icons.pause_circle_outline_rounded),
          )
        else
          IconButton(
            tooltip: context.tr(
              status == MonitorStatus.paused ? 'common.resume' : 'common.start',
            ),
            onPressed: onStart,
            icon: const Icon(Icons.play_circle_outline_rounded),
          ),
        IconButton(
          tooltip: context.tr('common.stop'),
          onPressed: status == MonitorStatus.stopped ? null : onStop,
          icon: const Icon(Icons.stop_circle_outlined),
        ),
      ],
    );
  }
}
