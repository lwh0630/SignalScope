import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/demo_mode.dart';
import '../../../core/history.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/theme/glass.dart';
import '../../../core/theme/glass_tokens.dart';
import '../../cellular/presentation/cellular_page.dart';
import '../../gnss/presentation/gnss_page.dart';
import '../../overview/presentation/overview_page.dart';
import '../../settings/presentation/settings_page.dart';
import '../../update/application/update_controller.dart';
import '../../update/presentation/update_prompt.dart';
import '../../wifi/presentation/wifi_page.dart';
import '../application/navigation.dart';

/// Always visible while demo mode is on so sample data can never be mistaken for real data.
class _DemoBanner extends ConsumerWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x2, Sp.x4, 0),
      child: GlassCard(
        tint: scheme.error,
        radius: Rd.md + 2,
        padding: const EdgeInsets.fromLTRB(Sp.x4, 2, Sp.x1, 2),
        child: Row(
          children: [
            Icon(Icons.science_outlined, size: 18, color: scheme.error),
            const SizedBox(width: Sp.x2),
            Expanded(
              child: Text(
                context.tr('demo.banner'),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                ref.read(historyProvider.notifier).clearAll();
                ref.read(demoModeProvider.notifier).set(false);
              },
              child: Text(context.tr('demo.turnOff')),
            ),
          ],
        ),
      ),
    );
  }
}

typedef _Destination = (IconData outlined, IconData filled, String label);

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(currentTabProvider);
    // Also starts the once-a-day background update check (see UpdateController).
    ref.listen(updateControllerProvider.select((s) => s.pendingPrompt), (
      _,
      release,
    ) {
      if (release == null || !context.mounted) return;
      ref.read(updateControllerProvider.notifier).consumePrompt();
      showUpdatePrompt(context, ref, release);
    });
    final destinations = <_Destination>[
      (
        Icons.dashboard_outlined,
        Icons.dashboard_rounded,
        context.tr('nav.overview'),
      ),
      (Icons.cell_tower_outlined, Icons.cell_tower, context.tr('nav.cellular')),
      (Icons.wifi_outlined, Icons.wifi, context.tr('nav.wifi')),
      (
        Icons.satellite_alt_outlined,
        Icons.satellite_alt,
        context.tr('nav.gnss'),
      ),
      (Icons.tune_outlined, Icons.tune, context.tr('nav.settings')),
    ];
    void select(int i) =>
        ref.read(currentTabProvider.notifier).select(AppTab.values[i]);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (ref.watch(demoModeProvider)) const _DemoBanner(),
            Expanded(
              // Swipe left / right between the pages, or tap the bar.
              child: _SwipePages(
                index: tab.index,
                onChanged: select,
                children: const [
                  OverviewPage(),
                  CellularPage(),
                  WifiPage(),
                  GnssPage(),
                  SettingsPage(),
                ],
              ),
            ),
          ],
        ),
      ),
      // The bar sits below the pages (like TokenBar's), so nothing scrolls under
      // it and the Scaffold removes the bottom inset from the pages' padding.
      bottomNavigationBar: _BottomBar(
        index: tab.index,
        onSelect: select,
        destinations: destinations,
      ),
    );
  }
}

/// Floating glass bottom bar: a pill that slides to the selected destination,
/// the same design as TokenBar's. The 6 px inner padding keeps the pill clear of
/// the rounded ends when the first or last destination is selected.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.index,
    required this.onSelect,
    required this.destinations,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final List<_Destination> destinations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final g = context.glass;
    final dark = theme.brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Sp.x4, Sp.x1, Sp.x4, Sp.x3),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: GlassSurface(
              radius: Rd.xl,
              padding: const EdgeInsets.all(6),
              child: SizedBox(
                height: 52,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth / destinations.length;
                    return Stack(
                      children: [
                        AnimatedPositioned(
                          duration: Motion.of(context, Motion.base),
                          curve: Motion.curve,
                          left: index * w,
                          top: 0,
                          bottom: 0,
                          width: w,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(Rd.lg),
                              color: accent.withValues(
                                alpha: dark ? 0.24 : 0.14,
                              ),
                              border: Border.all(
                                color: g.edgeLight.withValues(
                                  alpha: dark ? 0.12 : 0.55,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < destinations.length; i++)
                              Expanded(
                                child: Pressable(
                                  onTap: () => onSelect(i),
                                  semanticLabel: destinations[i].$3,
                                  builder:
                                      (context, hovered, pressed, focused) {
                                        final selected = index == i;
                                        final color = selected
                                            ? accent
                                            : theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.7);
                                        return Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              selected
                                                  ? destinations[i].$2
                                                  : destinations[i].$1,
                                              size: 22,
                                              color: color,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              destinations[i].$3,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                    color: color,
                                                    fontWeight: selected
                                                        ? FontWeight.w600
                                                        : FontWeight.w500,
                                                  ),
                                            ),
                                          ],
                                        );
                                      },
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A [PageView] bound to the shell's selected tab: a swipe reports the new
/// index, and a tab tap animates to it. Every page stays alive (like the
/// `IndexedStack` it replaces), so scroll positions survive a trip to another
/// tab. Sensors are still gated by the *selected tab* (`sensorVisibleProvider`),
/// which only changes once a swipe settles on a page.
///
/// A horizontally scrolling widget that overflows keeps its own drags; swipe on
/// any other part of the page, or tap the bar.
class _SwipePages extends StatefulWidget {
  const _SwipePages({
    required this.index,
    required this.onChanged,
    required this.children,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final List<Widget> children;

  @override
  State<_SwipePages> createState() => _SwipePagesState();
}

class _SwipePagesState extends State<_SwipePages> {
  late final PageController _controller = PageController(
    initialPage: widget.index,
  );

  /// True while a tab tap is animating across pages: the in-between pages the
  /// animation passes must not be reported as the user's choice.
  bool _animating = false;

  @override
  void didUpdateWidget(_SwipePages old) {
    super.didUpdateWidget(old);
    final shown = _controller.hasClients
        ? (_controller.page ?? widget.index.toDouble())
        : null;
    if (shown == null || shown.round() == widget.index) return;
    final duration = Motion.of(context, Motion.slow);
    if (duration == Duration.zero) {
      _controller.jumpToPage(widget.index);
      return;
    }
    _animating = true;
    _controller
        .animateToPage(widget.index, duration: duration, curve: Motion.curve)
        .whenComplete(() => _animating = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _controller,
      onPageChanged: (i) {
        if (!_animating) widget.onChanged(i);
      },
      children: [for (final page in widget.children) _KeepAlive(child: page)],
    );
  }
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
