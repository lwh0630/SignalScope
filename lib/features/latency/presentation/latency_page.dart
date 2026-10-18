import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/cards.dart';
import '../../../shared/widgets/mini_signal_bar.dart';
import '../application/latency_controller.dart';
import '../data/latency_targets.dart';

Color latencyColor(double ms) => switch (LatencyGrade.of(ms)) {
  LatencyGrade.excellent => SignalColors.excellent,
  LatencyGrade.good => SignalColors.good,
  LatencyGrade.fair => SignalColors.fair,
  LatencyGrade.poor => SignalColors.poor,
};

/// Full-screen latency test, opened from the speed icon on the overview page.
class LatencyPage extends ConsumerWidget {
  const LatencyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(latencyControllerProvider);
    // Rebuild when the user's custom list changes.
    ref.watch(settingsProvider.select((s) => s.customLatencyTargets));
    final c = ref.read(latencyControllerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('latency.title')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: state.running
                ? FilledButton.tonalIcon(
                    onPressed: c.stop,
                    icon: const Icon(Icons.stop_rounded),
                    label: Text(context.tr('latency.stop')),
                  )
                : FilledButton.icon(
                    onPressed: c.testAll,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(context.tr('latency.start')),
                  ),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (state.running) ...[
                _Progress(state: state),
                const SizedBox(height: 12),
              ],
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('latency.intro'),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr('latency.note'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _GroupCard(
                titleKey: 'latency.group.mainland',
                targets: LatencyTarget.mainland,
                state: state,
              ),
              const SizedBox(height: 12),
              _GroupCard(
                titleKey: 'latency.group.international',
                targets: LatencyTarget.international,
                state: state,
              ),
              const SizedBox(height: 12),
              _CustomCard(state: state, targets: c.customTargets),
            ],
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.state});

  final LatencyState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = state.total == 0 ? null : state.finished / state.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('latency.progress', [state.finished, state.total]),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        MiniSignalBar(fraction: fraction, color: theme.colorScheme.primary),
      ],
    );
  }
}

class _GroupCard extends ConsumerWidget {
  const _GroupCard({
    required this.titleKey,
    required this.targets,
    required this.state,
  });

  final String titleKey;
  final List<LatencyTarget> targets;
  final LatencyState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final avg = state.groupAverage(targets);
    return SectionCard(
      title: context.tr(titleKey),
      trailing: avg == null
          ? null
          : StatusPill(
              text: context.tr('latency.groupAvg', [avg.round()]),
              color: latencyColor(avg),
              icon: Icons.speed_rounded,
            ),
      child: Column(
        children: [
          for (var i = 0; i < targets.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            _TargetTile(
              target: targets[i],
              result: state.resultOf(targets[i].id),
            ),
          ],
        ],
      ),
    );
  }
}

class _TargetTile extends ConsumerWidget {
  const _TargetTile({
    required this.target,
    required this.result,
    this.onDelete,
  });

  final LatencyTarget target;
  final TargetResult result;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final stats = result.stats;
    final avg = stats?.avgMs;

    final Color color;
    final Widget trailing;
    switch (result.status) {
      case TargetStatus.idle:
        color = muted;
        trailing = Text(
          context.tr('latency.idle'),
          style: theme.textTheme.labelMedium?.copyWith(color: muted),
        );
      case TargetStatus.testing:
        color = theme.colorScheme.primary;
        trailing = const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case TargetStatus.done:
        color = latencyColor(avg!);
        trailing = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              avg.round().toString(),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 3),
            Text(
              'ms',
              style: theme.textTheme.labelMedium?.copyWith(color: muted),
            ),
          ],
        );
      case TargetStatus.failed:
        color = SignalColors.bad;
        trailing = Text(
          context.tr(
            result.failure == FailureKind.dns
                ? 'latency.failed.dns'
                : 'latency.failed.unreachable',
          ),
          style: theme.textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        );
    }

    final details = <String>[
      if (stats != null && stats.minMs != null)
        '${context.tr('latency.min')} ${stats.minMs!.round()}',
      if (stats != null && stats.maxMs != null)
        '${context.tr('latency.max')} ${stats.maxMs!.round()}',
      if (stats?.jitterMs != null)
        '${context.tr('latency.jitter')} ${stats!.jitterMs!.toStringAsFixed(1)}',
      if (stats != null && stats.sent > 0)
        '${context.tr('latency.loss')} ${stats.lossPercent.round()}%',
      if (stats?.dnsMs != null) 'DNS ${stats!.dnsMs!.round()} ms',
    ];

    return InkWell(
      onTap: result.status == TargetStatus.testing
          ? null
          : () => ref.read(latencyControllerProvider.notifier).testOne(target),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        target.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        target.displayAddress,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
                trailing,
                if (onDelete != null)
                  IconButton(
                    tooltip: context.tr('latency.custom.remove'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: onDelete,
                  ),
              ],
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Text(
                  details.join(' · '),
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
              ),
            ],
            if (avg != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 20),
                // Shorter bar = higher latency (0 ms full, 300 ms empty).
                child: MiniSignalBar(
                  fraction: (1 - avg / 300).clamp(0.04, 1.0),
                  color: color,
                  height: 5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CustomCard extends ConsumerStatefulWidget {
  const _CustomCard({required this.state, required this.targets});

  final LatencyState state;
  final List<LatencyTarget> targets;

  @override
  ConsumerState<_CustomCard> createState() => _CustomCardState();
}

class _CustomCardState extends ConsumerState<_CustomCard> {
  final _controller = TextEditingController();
  String? _errorKey;
  List<Object?> _errorArgs = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final outcome = ref
        .read(latencyControllerProvider.notifier)
        .addCustom(_controller.text);
    setState(() {
      switch (outcome) {
        case AddTargetOutcome.added:
          _errorKey = null;
          _controller.clear();
        case AddTargetOutcome.invalid:
          _errorKey = 'latency.custom.invalid';
        case AddTargetOutcome.duplicate:
          _errorKey = 'latency.custom.duplicate';
        case AddTargetOutcome.limitReached:
          _errorKey = 'latency.custom.limit';
          _errorArgs = [LatencyTarget.maxCustom];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = ref.read(latencyControllerProvider.notifier);
    final avg = widget.state.groupAverage(widget.targets);
    return SectionCard(
      title: context.tr('latency.group.custom'),
      trailing: avg == null
          ? null
          : StatusPill(
              text: context.tr('latency.groupAvg', [avg.round()]),
              color: latencyColor(avg),
              icon: Icons.speed_rounded,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  onSubmitted: (_) => _add(),
                  onChanged: (_) {
                    if (_errorKey != null) setState(() => _errorKey = null);
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: context.tr('latency.custom.hint'),
                    errorText: _errorKey == null
                        ? null
                        : context.tr(_errorKey!, _errorArgs),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _add,
                child: Text(context.tr('latency.custom.add')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.targets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                context.tr('latency.custom.empty'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (var i = 0; i < widget.targets.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
              _TargetTile(
                target: widget.targets[i],
                result: widget.state.resultOf(widget.targets[i].id),
                onDelete: () => c.removeCustom(widget.targets[i]),
              ),
            ],
        ],
      ),
    );
  }
}
