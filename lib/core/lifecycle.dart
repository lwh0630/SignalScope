import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/shell/application/navigation.dart';

/// True while the app is in the foreground. Listeners are released when the
/// app goes to the background and re-registered on resume.
class AppForegroundNotifier extends Notifier<bool> with WidgetsBindingObserver {
  @override
  bool build() {
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    ref.onDispose(() => binding.removeObserver(this));
    return _isForeground(binding.lifecycleState);
  }

  static bool _isForeground(AppLifecycleState? s) =>
      s == null ||
      s == AppLifecycleState.resumed ||
      s == AppLifecycleState.inactive;

  @override
  // The parameter cannot be named `state`: it would shadow Notifier.state.
  // ignore: avoid_renaming_method_parameters
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final fg = _isForeground(lifecycle);
    if (fg != state) state = fg;
  }
}

final appForegroundProvider =
    NotifierProvider<AppForegroundNotifier, bool>(AppForegroundNotifier.new);

/// Signal sources that can be monitored independently.
enum Sensor { cellular, wifi, gnss }

/// Whether [Sensor] should currently have native listeners registered.
///
/// A sensor is active only while the app is in the foreground and a page that
/// shows its data is visible. Leaving those pages unregisters the listeners.
final sensorVisibleProvider = Provider.family<bool, Sensor>((ref, sensor) {
  final foreground = ref.watch(appForegroundProvider);
  if (!foreground) return false;
  final tab = ref.watch(currentTabProvider);
  switch (sensor) {
    case Sensor.cellular:
      return tab == AppTab.overview || tab == AppTab.cellular;
    case Sensor.wifi:
      return tab == AppTab.overview || tab == AppTab.wifi;
    case Sensor.gnss:
      return tab == AppTab.overview || tab == AppTab.gnss;
  }
});
