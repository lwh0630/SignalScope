import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/demo_mode.dart';
import '../../../core/history.dart';
import '../../../core/i18n/strings.dart';
import '../../../shared/widgets/cards.dart';
import '../../export/export_service.dart';

/// History export (CSV / JSON) and clearing.
class DataCard extends ConsumerWidget {
  const DataCard({super.key});

  Future<void> _export(BuildContext context, WidgetRef ref, ExportFormat format) async {
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await ref.read(exportActionsProvider).export(format);
    if (!context.mounted) return;
    final text = switch (outcome.status) {
      ExportStatus.saved => context.tr('settings.exportDone', [outcome.location ?? '']),
      ExportStatus.empty => context.tr('settings.exportEmpty'),
      ExportStatus.failed => context.tr('settings.exportFail'),
    };
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final count = ref.watch(historyProvider.select((s) => s.series.values.fold<int>(0, (a, l) => a + l.length)));
    final demo = ref.watch(demoModeProvider);
    return SectionCard(
      title: context.tr('settings.data'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('settings.historySamples', [count]),
            style: theme.textTheme.bodyMedium,
          ),
          if (demo) ...[
            const SizedBox(height: 4),
            Text(
              context.tr('settings.exportDemoNote'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _export(context, ref, ExportFormat.csv),
                icon: const Icon(Icons.table_chart_outlined),
                label: Text(context.tr('settings.exportCsv')),
              ),
              FilledButton.icon(
                onPressed: () => _export(context, ref, ExportFormat.json),
                icon: const Icon(Icons.data_object_rounded),
                label: Text(context.tr('settings.exportJson')),
              ),
              OutlinedButton.icon(
                onPressed: count == 0
                    ? null
                    : () {
                        ref.read(historyProvider.notifier).clearAll();
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(content: Text(context.tr('settings.clearHistoryDone'))));
                      },
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(context.tr('settings.clearHistory')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Switch for the clearly labelled demo mode.
class DemoModeCard extends ConsumerWidget {
  const DemoModeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demo = ref.watch(demoModeProvider);
    return SectionCard(
      title: context.tr('settings.demo'),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(context.tr('settings.demoMode')),
        subtitle: Text(context.tr('settings.demoModeHint')),
        value: demo,
        onChanged: (v) {
          // Demo and real samples must never share a chart or an export.
          ref.read(historyProvider.notifier).clearAll();
          ref.read(demoModeProvider.notifier).set(v);
        },
      ),
    );
  }
}
