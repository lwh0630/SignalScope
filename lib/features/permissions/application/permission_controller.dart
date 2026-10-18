import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/lifecycle.dart';
import '../../../core/providers.dart';
import '../../../data/models/platform_info.dart';

/// Holds the latest permission + location-switch state.
///
/// It is refreshed when the app returns to the foreground, so changes made in
/// the system settings screen are picked up automatically.
class PermissionController extends Notifier<PermissionSnapshot> {
  bool _alive = true;

  @override
  PermissionSnapshot build() {
    _alive = true;
    // Switching platform (demo mode on/off) rebuilds this controller from scratch.
    ref.watch(signalPlatformProvider);
    ref.onDispose(() => _alive = false);
    ref.listen<bool>(appForegroundProvider, (prev, fg) {
      if (fg && prev == false) refresh();
    });
    Future.microtask(refresh);
    return const PermissionSnapshot.loading();
  }

  Future<void> refresh() async {
    final snap = await ref.read(signalPlatformProvider).getPermissions();
    if (_alive) state = snap;
  }

  Future<void> request(Set<PermGroup> groups) async {
    final snap = await ref
        .read(signalPlatformProvider)
        .requestPermissions(groups);
    if (_alive) state = snap;
  }

  Future<void> openAppSettings() =>
      ref.read(signalPlatformProvider).openAppSettings();

  Future<void> openLocationSettings() =>
      ref.read(signalPlatformProvider).openLocationSettings();
}

final permissionProvider =
    NotifierProvider<PermissionController, PermissionSnapshot>(
      PermissionController.new,
    );
