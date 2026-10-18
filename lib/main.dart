import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/providers.dart';
import 'data/platform/platform_factory.dart';
import 'features/settings/domain/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final platform = createSignalPlatform();
  final settings = AppSettings.fromJson(await platform.loadSettings());
  runApp(
    ProviderScope(
      overrides: [
        realPlatformProvider.overrideWithValue(platform),
        initialSettingsProvider.overrideWithValue(settings),
      ],
      child: const SignalScopeApp(),
    ),
  );
}
