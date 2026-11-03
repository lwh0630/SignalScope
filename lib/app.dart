import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/theme/ambient_background.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/background.dart';
import 'features/shell/presentation/home_shell.dart';

class SignalScopeApp extends ConsumerWidget {
  const SignalScopeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    final (style, imagePath, dim) = ref.watch(
      settingsProvider.select(
        (s) => (s.background, s.backgroundImage, s.backgroundDim),
      ),
    );
    return MaterialApp(
      title: 'SignalScope',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeResolutionCallback: (device, supported) {
        if (device != null) {
          for (final s in supported) {
            if (s.languageCode == device.languageCode) return s;
          }
        }
        return const Locale('en');
      },
      // The ambient glow (or the user's picture) sits under the Navigator;
      // every Scaffold is transparent.
      builder: (context, child) => AmbientBackground(
        style: style,
        image: style == BackgroundStyle.image
            ? backgroundImageProvider(imagePath)
            : null,
        dim: dim,
        child: child,
      ),
      home: const HomeShell(),
    );
  }
}
