import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/platform/demo_platform.dart';
import '../data/platform/platform_factory.dart';
import '../data/platform/signal_platform.dart';
import '../features/settings/domain/app_settings.dart';
import 'demo_mode.dart';

/// The real host platform adapter. Overridden in `main()`.
final realPlatformProvider = Provider<SignalPlatform>((ref) => createSignalPlatform());

/// The adapter every feature reads from: the real platform, or the clearly
/// labelled demo platform while demo mode is on. Overridden directly in tests.
final signalPlatformProvider = Provider<SignalPlatform>((ref) {
  final real = ref.watch(realPlatformProvider);
  return ref.watch(demoModeProvider) ? DemoPlatform(real) : real;
});

/// Settings loaded before `runApp`. Overridden in `main()` and tests.
final initialSettingsProvider = Provider<AppSettings>((ref) => const AppSettings());

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  void update(AppSettings Function(AppSettings current) change) {
    final next = change(state);
    state = next;
    ref.read(signalPlatformProvider).saveSettings(next.toJson());
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
