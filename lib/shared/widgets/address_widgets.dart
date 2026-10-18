import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n/strings.dart';
import '../../core/utils/format.dart';
import 'cards.dart';

/// Copies [text] and confirms with a snack bar.
Future<void> copyToClipboard(BuildContext context, String text) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = context.tr('addr.copied', [text]);
  await Clipboard.setData(ClipboardData(text: text));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
}

/// [InfoRow] whose value is copied on long press.
class CopyableInfoRow extends StatelessWidget {
  const CopyableInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.note,
  });

  final String label;
  final String? value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: v == null || v.isEmpty
          ? null
          : () => copyToClipboard(context, v),
      child: InfoRow(label: label, value: v, note: note),
    );
  }
}

class AddressEntry {
  const AddressEntry(this.label, this.value, {this.hint});

  final String label;

  /// `null` renders as `--`.
  final String? value;

  /// Shown instead of `--` when the value is missing, to explain why.
  final String? hint;
}

/// Compact "label  value" lines for the overview cards. Long-press a value to copy it.
class AddressLines extends StatelessWidget {
  const AddressLines({super.key, required this.entries});

  final List<AddressEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in entries)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: e.value == null
                ? null
                : () => copyToClipboard(context, e.value!),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 104,
                    child: Text(
                      e.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: muted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.value ?? (e.hint ?? kUnavailable),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: e.value == null
                            ? FontWeight.w400
                            : FontWeight.w600,
                        color: e.value == null
                            ? muted.withValues(alpha: 0.8)
                            : null,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
