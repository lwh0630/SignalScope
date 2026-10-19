import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/cards.dart';
import '../application/update_controller.dart';

/// Settings card: version, automatic check switch, manual check and the
/// download / install flow of the in-app updater.
class UpdateCard extends ConsumerWidget {
  const UpdateCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(signalPlatformProvider).isAndroid) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final state = ref.watch(updateControllerProvider);
    final controller = ref.read(updateControllerProvider.notifier);
    final auto = ref.watch(settingsProvider.select((s) => s.autoCheckUpdates));
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return SectionCard(
      title: context.tr('update.title'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('settings.version', [
              state.current?.versionName ??
                  ref.watch(installedVersionProvider).value ??
                  kAppVersion,
            ]),
            style: theme.textTheme.bodyMedium,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('update.auto')),
            subtitle: Text(context.tr('update.autoHint')),
            value: auto,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .update((c) => c.copyWith(autoCheckUpdates: v)),
          ),
          const SizedBox(height: 4),
          ..._body(context, state, controller, theme, muted),
        ],
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    UpdateState state,
    UpdateController controller,
    ThemeData theme,
    TextStyle? muted,
  ) {
    final release = state.release;
    final checkButton = FilledButton.icon(
      onPressed: state.busy ? null : () => controller.check(),
      icon: state.phase == UpdatePhase.checking
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.system_update_alt_rounded),
      label: Text(
        context.tr(
          state.phase == UpdatePhase.checking
              ? 'update.checking'
              : 'update.check',
        ),
      ),
    );

    switch (state.phase) {
      case UpdatePhase.available when release != null:
        return [
          Text(
            context.tr('update.available', [release.tag]),
            style: theme.textTheme.titleSmall?.copyWith(
              color: SignalColors.excellent,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (release.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              release.notes,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: controller.downloadAndInstall,
                icon: const Icon(Icons.download_rounded),
                label: Text(context.tr('update.download')),
              ),
              OutlinedButton(
                onPressed: () => controller.check(),
                child: Text(context.tr('update.check')),
              ),
            ],
          ),
        ];
      case UpdatePhase.downloading:
        final p = state.progress;
        return [
          Text(
            p == null
                ? context.tr('update.downloadingUnknown')
                : context.tr('update.downloading', [(p * 100).round()]),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: p),
          const SizedBox(height: 8),
          TextButton(
            onPressed: controller.cancelDownload,
            child: Text(context.tr('update.cancel')),
          ),
        ];
      case UpdatePhase.needPermission:
        return [
          Text(context.tr('update.needPermission'), style: muted),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: controller.openInstallPermissionSettings,
                icon: const Icon(Icons.settings_outlined),
                label: Text(context.tr('update.openPermission')),
              ),
              OutlinedButton(
                onPressed: controller.installDownloaded,
                child: Text(context.tr('update.continueInstall')),
              ),
            ],
          ),
        ];
      case UpdatePhase.installStarted:
        return [
          Text(context.tr('update.installStarted'), style: muted),
          const SizedBox(height: 12),
          checkButton,
        ];
      case UpdatePhase.upToDate:
        return [
          Text(
            context.tr('update.upToDate'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: SignalColors.excellent,
            ),
          ),
          const SizedBox(height: 12),
          checkButton,
        ];
      case UpdatePhase.error:
        return [
          Text(
            context.tr('update.err.${state.errorCode ?? 'network'}'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 12),
          checkButton,
        ];
      case UpdatePhase.available:
      case UpdatePhase.checking:
      case UpdatePhase.idle:
        return [
          Text(context.tr('update.privacy'), style: muted),
          const SizedBox(height: 12),
          checkButton,
        ];
    }
  }
}
