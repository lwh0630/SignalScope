import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../shell/application/navigation.dart';
import '../application/update_controller.dart';
import '../data/update_repository.dart';

/// Asks once whether to install the update a background check just found.
/// "Update" opens Settings, where the download progress is shown.
Future<void> showUpdatePrompt(
  BuildContext context,
  WidgetRef ref,
  ReleaseInfo release,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.tr('update.prompt.title')),
      content: Text(
        ctx.tr('update.prompt.body', [
          release.tag,
          ref.read(updateControllerProvider).current?.versionName ?? '',
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(ctx.tr('update.later')),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            ref.read(currentTabProvider.notifier).select(AppTab.settings);
            ref.read(updateControllerProvider.notifier).downloadAndInstall();
          },
          child: Text(ctx.tr('update.now')),
        ),
      ],
    ),
  );
}
