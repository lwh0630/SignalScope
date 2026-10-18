import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Demo mode swaps the real platform adapter for built-in sample data so the
/// UI can be explored without a SIM, Wi-Fi or satellites.
///
/// It is deliberately **session only**: it is never persisted and always
/// starts switched off, so demo samples can not silently end up in a real
/// measurement session. While active the whole app shows a banner and exports
/// are labelled as demo data.
class DemoModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool enabled) => state = enabled;
}

final demoModeProvider = NotifierProvider<DemoModeNotifier, bool>(
  DemoModeNotifier.new,
);
