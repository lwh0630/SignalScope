import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/cards.dart';
import '../../../shared/widgets/page_scaffold.dart';
import '../../permissions/presentation/permission_manager_card.dart';
import '../../update/presentation/update_card.dart';
import '../domain/app_settings.dart';
import 'data_card.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return PageScaffold(
      title: context.tr('settings.title'),
      children: [
        SectionCard(
          title: context.tr('settings.appearance'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('settings.theme'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(context.tr('settings.theme.dark')),
                    icon: const Icon(Icons.dark_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(context.tr('settings.theme.light')),
                    icon: const Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(context.tr('settings.theme.system')),
                    icon: const Icon(Icons.brightness_auto_outlined),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (s) =>
                    notifier.update((c) => c.copyWith(themeMode: s.first)),
              ),
              const SizedBox(height: 16),
              Text(
                context.tr('settings.language'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: 'system',
                    label: Text(context.tr('settings.language.system')),
                  ),
                  ButtonSegment(
                    value: 'zh',
                    label: Text(context.tr('settings.language.zh')),
                  ),
                  ButtonSegment(
                    value: 'en',
                    label: Text(context.tr('settings.language.en')),
                  ),
                ],
                selected: {settings.languageCode},
                onSelectionChanged: (s) =>
                    notifier.update((c) => c.copyWith(languageCode: s.first)),
              ),
            ],
          ),
        ),
        SectionCard(
          title: context.tr('settings.monitoring'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('settings.updateRate'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  for (final ms in AppSettings.updateIntervalOptionsMs)
                    ButtonSegment(
                      value: ms,
                      label: Text(
                        ms >= 1000
                            ? context.tr('settings.seconds', [ms ~/ 1000])
                            : context.tr('settings.milliseconds', [ms]),
                      ),
                    ),
                ],
                selected: {settings.updateIntervalMs},
                onSelectionChanged: (s) => notifier.update(
                  (c) => c.copyWith(updateIntervalMs: s.first),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.tr('settings.updateRateHint'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          title: context.tr('settings.history'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('settings.recordHistory')),
                subtitle: Text(context.tr('settings.recordHistoryHint')),
                value: settings.recordHistory,
                onChanged: (v) =>
                    notifier.update((c) => c.copyWith(recordHistory: v)),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('settings.historyWindow'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: 60,
                    label: Text(context.tr('settings.seconds', [60])),
                  ),
                  ButtonSegment(
                    value: 300,
                    label: Text(context.tr('settings.minutes', [5])),
                  ),
                ],
                selected: {settings.historySeconds},
                onSelectionChanged: (s) =>
                    notifier.update((c) => c.copyWith(historySeconds: s.first)),
              ),
            ],
          ),
        ),
        const DataCard(),
        const PermissionManagerCard(),
        const DemoModeCard(),
        const UpdateCard(),
        SectionCard(
          title: context.tr('settings.about'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SignalScope', style: theme.textTheme.titleMedium),
              Text(
                context.tr('settings.version', [
                  ref.watch(installedVersionProvider).value ?? kAppVersion,
                ]),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('settings.aboutBody'),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
