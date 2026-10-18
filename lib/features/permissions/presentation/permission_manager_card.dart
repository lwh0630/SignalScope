import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/platform_info.dart';
import '../../../shared/widgets/cards.dart';
import '../application/permission_controller.dart';

/// Settings card listing every permission SignalScope uses, why, and the
/// right action: request it, or open system settings once it is permanently denied.
class PermissionManagerCard extends ConsumerWidget {
  const PermissionManagerCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(signalPlatformProvider);
    final theme = Theme.of(context);
    if (!platform.isAndroid) {
      return SectionCard(
        title: context.tr('settings.permissions'),
        child: Text(
          context.tr('settings.permissionsUnsupported'),
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    final snap = ref.watch(permissionProvider);
    final controller = ref.read(permissionProvider.notifier);

    return SectionCard(
      title: context.tr('settings.permissions'),
      trailing: IconButton(
        tooltip: context.tr('common.refresh'),
        icon: const Icon(Icons.refresh_rounded),
        onPressed: controller.refresh,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final g in PermGroup.values) ...[
            _PermissionRow(group: g, status: snap.of(g), controller: controller),
            const Divider(height: 1),
          ],
          _LocationSwitchRow(enabled: snap.locationServicesEnabled, controller: controller),
          const SizedBox(height: 8),
          Text(
            context.tr('settings.permissionsHint'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

(Color, String) _statusStyle(PermStatus s) => switch (s) {
      PermStatus.granted => (SignalColors.excellent, 'perm.status.granted'),
      PermStatus.denied => (SignalColors.fair, 'perm.status.denied'),
      PermStatus.permanentlyDenied => (SignalColors.bad, 'perm.status.permanentlyDenied'),
      PermStatus.notApplicable => (SignalColors.none, 'perm.status.notApplicable'),
    };

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.group, required this.status, required this.controller});

  final PermGroup group;
  final PermStatus status;
  final PermissionController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, key) = _statusStyle(status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('perm.group.${group.name}'),
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              StatusPill(text: context.tr(key), color: color),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            context.tr('perm.group.${group.name}.desc'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (status == PermStatus.denied || status == PermStatus.permanentlyDenied) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: status == PermStatus.denied
                  ? FilledButton.tonal(
                      onPressed: () => controller.request({group}),
                      child: Text(context.tr('common.grant')),
                    )
                  : FilledButton.tonal(
                      onPressed: controller.openAppSettings,
                      child: Text(context.tr('perm.openAppSettings')),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LocationSwitchRow extends StatelessWidget {
  const _LocationSwitchRow({required this.enabled, required this.controller});

  final bool? enabled;
  final PermissionController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, label) = switch (enabled) {
      true => (SignalColors.excellent, context.tr('perm.switch.on')),
      false => (SignalColors.bad, context.tr('perm.switch.off')),
      null => (SignalColors.none, context.tr('common.unavailable')),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('perm.locationSwitch'),
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              StatusPill(text: label, color: color),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            context.tr('perm.locationSwitch.desc'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (enabled == false) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: controller.openLocationSettings,
                child: Text(context.tr('perm.openLocationSettings')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
