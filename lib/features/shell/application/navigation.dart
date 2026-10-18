import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom navigation tabs, in display order.
enum AppTab { overview, cellular, wifi, gnss, settings }

class CurrentTabNotifier extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.overview;

  void select(AppTab tab) => state = tab;
}

final currentTabProvider = NotifierProvider<CurrentTabNotifier, AppTab>(CurrentTabNotifier.new);
