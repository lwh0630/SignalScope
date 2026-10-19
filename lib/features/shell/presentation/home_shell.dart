import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/demo_mode.dart';
import '../../../core/history.dart';
import '../../../core/i18n/strings.dart';
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
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Icon(
              Icons.science_outlined,
              size: 18,
              color: scheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.tr('demo.banner'),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onErrorContainer,
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
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (ref.watch(demoModeProvider)) const _DemoBanner(),
            Expanded(
              child: IndexedStack(
                index: tab.index,
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab.index,
        onDestinationSelected: (i) =>
            ref.read(currentTabProvider.notifier).select(AppTab.values[i]),
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
    );
  }
}
