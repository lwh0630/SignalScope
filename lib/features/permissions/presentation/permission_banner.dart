import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../data/models/platform_info.dart';
import '../application/permission_controller.dart';

/// Explains a missing permission (or disabled location switch) and offers the
/// right action: request it, or open system settings when the user chose
/// "don't ask again".
class PermissionBanner extends ConsumerWidget {
  const PermissionBanner({
    super.key,
    required this.groups,
    required this.messageKey,
    this.needsLocationServices = false,
  });

  final Set<PermGroup> groups;

  /// i18n key explaining why these permissions are needed.
  final String messageKey;

  /// Also require the system location switch (Wi-Fi scan results, GNSS).
  final bool needsLocationServices;

  /// Whether the banner has anything to say for [snap].
  static bool isNeeded(
    PermissionSnapshot snap,
    Set<PermGroup> groups, {
    bool needsLocationServices = false,
  }) {
    final missing = groups.any((g) {
      final s = snap.of(g);
      return s == PermStatus.denied || s == PermStatus.permanentlyDenied;
    });
    return missing ||
        (needsLocationServices && snap.locationServicesEnabled == false);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(permissionProvider);
    if (!isNeeded(snap, groups, needsLocationServices: needsLocationServices)) {
      return const SizedBox.shrink();
    }
    final controller = ref.read(permissionProvider.notifier);
    final theme = Theme.of(context);

    final missing = groups
        .where(
          (g) =>
              snap.of(g) == PermStatus.denied ||
              snap.of(g) == PermStatus.permanentlyDenied,
        )
        .toSet();
    final permanent = missing.any(
      (g) => snap.of(g) == PermStatus.permanentlyDenied,
    );

    final String message;
    final String actionLabel;
    final VoidCallback action;
    if (missing.isNotEmpty) {
      message = context.tr(messageKey);
      if (permanent) {
        actionLabel = context.tr('perm.openAppSettings');
        action = controller.openAppSettings;
      } else {
        actionLabel = context.tr('common.grant');
        action = () => controller.request(missing);
      }
    } else {
      message = context.tr('perm.locationOff');
      actionLabel = context.tr('perm.openLocationSettings');
      action = controller.openLocationSettings;
    }

    return Card(
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(message, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
            if (missing.isNotEmpty && permanent) ...[
              const SizedBox(height: 6),
              Text(
                context.tr('perm.permanentHint'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: action,
                child: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
