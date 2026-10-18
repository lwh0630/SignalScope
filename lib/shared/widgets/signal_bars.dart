import 'package:flutter/material.dart';

/// Four-bar signal strength icon. [bars] is 0..4.
class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.bars, required this.color, this.size = 22});

  final int bars;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final off = Theme.of(context).colorScheme.surfaceContainerHighest;
    return SizedBox(
      width: size,
      height: size,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 1; i <= 4; i++)
            Container(
              width: size / 6,
              height: size * (0.25 + 0.75 * i / 4),
              decoration: BoxDecoration(
                color: i <= bars ? color : off,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}
