import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/providers.dart';
import '../../../core/theme/background.dart';
import '../../../core/theme/glass.dart';
import '../../../core/theme/glass_tokens.dart';
import '../domain/app_settings.dart';

/// Settings control for the app background: gradient presets, plus a picture of
/// the user's own where the platform can pick one (Android).
class BackgroundPicker extends ConsumerStatefulWidget {
  const BackgroundPicker({super.key});

  @override
  ConsumerState<BackgroundPicker> createState() => _BackgroundPickerState();
}

class _BackgroundPickerState extends ConsumerState<BackgroundPicker> {
  bool _busy = false;

  Future<void> _pickImage() async {
    if (_busy) return;
    final platform = ref.read(signalPlatformProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failed = context.tr('background.failed');
    setState(() => _busy = true);
    try {
      final path = await platform.pickBackgroundImage();
      if (path != null) {
        final old = ref.read(settingsProvider).backgroundImage;
        notifier.update(
          (c) => c.copyWith(
            background: BackgroundStyle.image,
            backgroundImage: path,
          ),
        );
        if (old.isNotEmpty && old != path) {
          await platform.deleteBackgroundImage(old);
        }
      }
    } on Object {
      messenger?.showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeImage() async {
    final platform = ref.read(signalPlatformProvider);
    final old = ref.read(settingsProvider).backgroundImage;
    ref
        .read(settingsProvider.notifier)
        .update(
          (c) => c.copyWith(
            background: BackgroundStyle.aurora,
            backgroundImage: '',
          ),
        );
    await platform.deleteBackgroundImage(old);
  }

  void _select(BackgroundStyle style) {
    final s = ref.read(settingsProvider);
    if (style == BackgroundStyle.image && s.backgroundImage.isEmpty) {
      _pickImage();
      return;
    }
    ref
        .read(settingsProvider.notifier)
        .update((c) => c.copyWith(background: style));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = ref.watch(settingsProvider);
    final canPickImage = ref.watch(
      signalPlatformProvider.select((p) => p.supportsBackgroundImage),
    );
    final styles = [
      ...BackgroundStyle.values.where((b) => b.isPreset),
      if (canPickImage) BackgroundStyle.image,
    ];
    final onImage =
        s.background == BackgroundStyle.image && s.backgroundImage.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('settings.background'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: Sp.x3),
        Wrap(
          spacing: Sp.x3,
          runSpacing: Sp.x3,
          children: [
            for (final style in styles)
              _Swatch(
                key: ValueKey('background.${style.name}'),
                style: style,
                label: context.tr('background.${style.name}'),
                selected: s.background == style,
                imagePath: style == BackgroundStyle.image
                    ? s.backgroundImage
                    : '',
                onTap: () => _select(style),
              ),
          ],
        ),
        if (onImage) ...[
          const SizedBox(height: Sp.x4),
          Wrap(
            spacing: Sp.x2,
            runSpacing: Sp.x2,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickImage,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(context.tr('background.change')),
              ),
              TextButton.icon(
                onPressed: _removeImage,
                icon: const Icon(Icons.delete_outline),
                label: Text(context.tr('background.remove')),
              ),
            ],
          ),
          const SizedBox(height: Sp.x3),
          Text(context.tr('background.dim'), style: theme.textTheme.bodyMedium),
          Slider(
            value: s.backgroundDim.clamp(0.0, AppSettings.maxBackgroundDim),
            max: AppSettings.maxBackgroundDim,
            divisions: 17,
            label: '${(s.backgroundDim * 100).round()}%',
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .update((c) => c.copyWith(backgroundDim: v)),
          ),
          Text(
            context.tr('background.dimHint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    required this.style,
    required this.label,
    required this.selected,
    required this.imagePath,
    required this.onTap,
  });

  final BackgroundStyle style;
  final String label;
  final bool selected;
  final String imagePath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = context.glass;
    final accent = theme.colorScheme.primary;
    final palette = BackgroundPalette.of(style, g);
    final image = style == BackgroundStyle.image
        ? backgroundImageProvider(imagePath, maxSide: 240)
        : null;
    const w = 84.0, h = 52.0;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      builder: (context, hovered, pressed, focused) => SizedBox(
        width: w,
        child: Column(
          children: [
            AnimatedContainer(
              duration: Motion.of(context, Motion.fast),
              width: w,
              height: h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Rd.md),
                border: Border.all(
                  color: selected
                      ? accent
                      : (hovered ? g.edgeLight : g.hairline),
                  width: selected ? 2 : 1,
                ),
                gradient: image == null
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.alphaBlend(
                            palette.a.withValues(alpha: 0.75),
                            palette.base,
                          ),
                          Color.alphaBlend(
                            palette.b.withValues(alpha: 0.65),
                            palette.base,
                          ),
                          Color.alphaBlend(
                            palette.c.withValues(alpha: 0.75),
                            palette.base,
                          ),
                        ],
                      )
                    : null,
                image: image == null
                    ? null
                    : DecorationImage(image: image, fit: BoxFit.cover),
              ),
              child: style == BackgroundStyle.image && image == null
                  ? Icon(
                      Icons.add_photo_alternate_outlined,
                      color: theme.colorScheme.onSurface,
                    )
                  : (selected
                        ? const Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: EdgeInsets.all(3),
                              child: Icon(
                                Icons.check_circle,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : null),
            ),
            const SizedBox(height: Sp.x1),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: selected ? accent : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
