import 'package:flutter/material.dart';

/// Thin horizontal bar that animates to [fraction] (0..1). `null` shows an
/// empty track: there is no value, which is different from a weak value.
class MiniSignalBar extends StatelessWidget {
  const MiniSignalBar({
    super.key,
    required this.fraction,
    required this.color,
    this.height = 8,
  });

  final double? fraction;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: fraction ?? 0),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: track),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0.0, 1.0),
                child: ColoredBox(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
