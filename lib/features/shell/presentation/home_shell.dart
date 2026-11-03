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

/// Height of the floating navigation bar and the gap around it. Pages add it to
/// their bottom padding (through [MediaQuery]) so nothing ends up under the bar.
const double _navBarHeight = 64;
const double _navBarGap = Sp.x3;

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
    final mq = MediaQuery.of(context);
    final safeBottom = mq.padding.bottom;
    final barBottom = safeBottom > _navBarGap ? safeBottom : _navBarGap;
    final reserved = _navBarHeight + barBottom + _navBarGap;
    return Scaffold(
      // The pages scroll under the floating bar; they pad themselves by [reserved].
      body: Stack(
        children: [
          Positioned.fill(
            child: MediaQuery(
              data: mq.copyWith(padding: mq.padding.copyWith(bottom: reserved)),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    if (ref.watch(demoModeProvider)) const _DemoBanner(),
                    Expanded(
                      // Swipe left / right between the pages, or tap the bar.
                      child: _SwipePages(
                        index: tab.index,
                        onChanged: (i) => ref
                            .read(currentTabProvider.notifier)
                            .select(AppTab.values[i]),
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
            ),
          ),
          Positioned(
            left: Sp.x4,
            right: Sp.x4,
            bottom: barBottom,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: GlassSurface(
                  radius: 30,
                  // NavigationBar wraps itself in a SafeArea; the shell already places the
                  // pill clear of the system bars.
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    removeBottom: true,
                    child: NavigationBar(
                      height: _navBarHeight,
                      selectedIndex: tab.index,
                      onDestinationSelected: (i) => ref
                          .read(currentTabProvider.notifier)
                          .select(AppTab.values[i]),
                      destinations: [
                        NavigationDestination(
                          icon: const Icon(Icons.dashboard_outlined),
                          selectedIcon: const Icon(Icons.dashboard_rounded),
                          label: context.tr('nav.overview'),
                        ),
                        NavigationDestination(
                          icon: const Icon(Icons.cell_tower_outlined),
                          selectedIcon: const Icon(Icons.cell_tower),
                          label: context.tr('nav.cellular'),
                        ),
                        NavigationDestination(
                          icon: const Icon(Icons.wifi_outlined),
                          selectedIcon: const Icon(Icons.wifi),
                          label: context.tr('nav.wifi'),
                        ),
                        NavigationDestination(
                          icon: const Icon(Icons.satellite_alt_outlined),
                          selectedIcon: const Icon(Icons.satellite_alt),
                          label: context.tr('nav.gnss'),
                        ),
                        NavigationDestination(
                          icon: const Icon(Icons.tune_outlined),
                          selectedIcon: const Icon(Icons.tune),
                          label: context.tr('nav.settings'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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
