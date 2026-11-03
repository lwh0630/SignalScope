import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application/app.dart';
import 'package:flutter_application/core/providers.dart';
import 'package:flutter_application/core/theme/ambient_background.dart';
import 'package:flutter_application/core/theme/background.dart';
import 'package:flutter_application/core/theme/glass_tokens.dart';
import 'package:flutter_application/features/settings/domain/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// A 1x1 PNG, so a "picked picture" is a real, decodable file.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _PickerPlatform extends FakeAndroidPlatform {
  _PickerPlatform({this.picked, this.fail = false});

  String? picked;
  final bool fail;
  final deleted = <String>[];

  @override
  bool get supportsBackgroundImage => true;

  @override
  Future<String?> pickBackgroundImage() async {
    if (fail) throw StateError('not a picture');
    return picked;
  }

  @override
  Future<void> deleteBackgroundImage(String path) async => deleted.add(path);
}

Future<ProviderContainer> _openSettings(
  WidgetTester tester,
  FakeAndroidPlatform platform, {
  AppSettings initial = const AppSettings(),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        signalPlatformProvider.overrideWithValue(platform),
        initialSettingsProvider.overrideWithValue(initial),
      ],
      child: const SignalScopeApp(),
    ),
  );
  await tester.pump();
  await tester.tap(find.byIcon(Icons.tune_outlined));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(SignalScopeApp)));
}

void main() {
  group('AppSettings background', () {
    test('defaults to the aurora glow', () {
      const s = AppSettings();
      expect(s.background, BackgroundStyle.aurora);
      expect(s.backgroundImage, '');
      expect(s.backgroundDim, AppSettings.defaultBackgroundDim);
    });

    test('survives a JSON round trip', () {
      final s = const AppSettings().copyWith(
        background: BackgroundStyle.image,
        backgroundImage: '/files/backgrounds/bg_1.img',
        backgroundDim: 0.6,
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.background, BackgroundStyle.image);
      expect(back.backgroundImage, '/files/backgrounds/bg_1.img');
      expect(back.backgroundDim, 0.6);
    });

    test('settings saved before this feature still load', () {
      final s = AppSettings.fromJson('{"themeMode":"light"}');
      expect(s.themeMode, ThemeMode.light);
      expect(s.background, BackgroundStyle.aurora);
    });

    test('bad values fall back instead of breaking the app', () {
      final unknown = AppSettings.fromJson('{"background":"neon"}');
      expect(unknown.background, BackgroundStyle.aurora);

      // A picture style without a picture cannot be shown.
      final noFile = AppSettings.fromJson(
        '{"background":"image","backgroundImage":""}',
      );
      expect(noFile.background, BackgroundStyle.aurora);

      expect(
        AppSettings.fromJson('{"backgroundDim":9}').backgroundDim,
        AppSettings.maxBackgroundDim,
      );
      expect(AppSettings.fromJson('{"backgroundDim":-1}').backgroundDim, 0);
      expect(
        AppSettings.fromJson('{"backgroundDim":"x"}').backgroundDim,
        AppSettings.defaultBackgroundDim,
      );
    });
  });

  group('BackgroundPalette', () {
    test('every preset has its own palette in both brightnesses', () {
      for (final g in [GlassColors.light, GlassColors.dark]) {
        final palettes = {
          for (final s in BackgroundStyle.values.where((s) => s.isPreset))
            s: BackgroundPalette.of(s, g),
        };
        expect(palettes.values.toSet().length, palettes.length);
      }
    });

    test('aurora is the theme glow and a picture falls back to it', () {
      final aurora = BackgroundPalette.of(
        BackgroundStyle.aurora,
        GlassColors.dark,
      );
      expect(aurora.base, GlassColors.dark.base);
      expect(aurora.a, GlassColors.dark.glowA);
      expect(
        BackgroundPalette.of(BackgroundStyle.image, GlassColors.dark),
        aurora,
      );
    });

    test('no picture path means no image provider', () {
      expect(backgroundImageProvider(''), isNull);
      expect(backgroundImageProvider('/x/y.img'), isNotNull);
    });
  });

  testWidgets('the background setting reaches the ambient layer', (
    tester,
  ) async {
    final container = await _openSettings(tester, FakeAndroidPlatform());
    AmbientBackground ambient() =>
        tester.widget<AmbientBackground>(find.byType(AmbientBackground));
    expect(ambient().style, BackgroundStyle.aurora);

    container
        .read(settingsProvider.notifier)
        .update((c) => c.copyWith(background: BackgroundStyle.ocean));
    await tester.pump();
    expect(ambient().style, BackgroundStyle.ocean);
  });

  testWidgets('presets are listed and selectable; no picture swatch here', (
    tester,
  ) async {
    final container = await _openSettings(tester, FakeAndroidPlatform());
    for (final s in BackgroundStyle.values.where((s) => s.isPreset)) {
      expect(find.byKey(ValueKey('background.${s.name}')), findsOneWidget);
    }
    // The platform cannot pick pictures, so the picture swatch is hidden.
    expect(find.byKey(const ValueKey('background.image')), findsNothing);

    final sunset = find.byKey(const ValueKey('background.sunset'));
    await tester.ensureVisible(sunset);
    await tester.tap(sunset);
    await tester.pump();
    expect(container.read(settingsProvider).background, BackgroundStyle.sunset);
  });

  group('custom picture', () {
    late Directory dir;
    late String file;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('signalscope_bg_');
      file = '${dir.path}${Platform.pathSeparator}bg_1.img';
      File(file).writeAsBytesSync(_png);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    testWidgets('picking a picture selects it and shows the controls', (
      tester,
    ) async {
      final platform = _PickerPlatform(picked: file);
      final container = await _openSettings(tester, platform);
      final swatch = find.byKey(const ValueKey('background.image'));
      await tester.ensureVisible(swatch);
      // Nothing to change or remove before a picture exists.
      expect(find.byType(Slider), findsNothing);

      await tester.tap(swatch);
      await tester.pump();
      await tester.pump();

      final s = container.read(settingsProvider);
      expect(s.background, BackgroundStyle.image);
      expect(s.backgroundImage, file);
      expect(find.byType(Slider), findsOneWidget);
      expect(platform.deleted, isEmpty);
    });

    testWidgets('changing the picture deletes the previous file', (
      tester,
    ) async {
      final platform = _PickerPlatform(picked: '${file}2');
      final container = await _openSettings(
        tester,
        platform,
        initial: AppSettings(
          background: BackgroundStyle.image,
          backgroundImage: file,
        ),
      );
      await tester.tap(find.text('Change picture'));
      await tester.pump();
      await tester.pump();

      expect(container.read(settingsProvider).backgroundImage, '${file}2');
      expect(platform.deleted, [file]);
    });

    testWidgets('removing the picture goes back to the glow', (tester) async {
      final platform = _PickerPlatform();
      final container = await _openSettings(
        tester,
        platform,
        initial: AppSettings(
          background: BackgroundStyle.image,
          backgroundImage: file,
        ),
      );
      final remove = find.text('Remove picture');
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pump();

      final s = container.read(settingsProvider);
      expect(s.background, BackgroundStyle.aurora);
      expect(s.backgroundImage, '');
      expect(platform.deleted, [file]);
    });

    testWidgets('the overlay slider sets the dim strength', (tester) async {
      final container = await _openSettings(
        tester,
        _PickerPlatform(),
        initial: AppSettings(
          background: BackgroundStyle.image,
          backgroundImage: file,
        ),
      );
      final slider = find.byType(Slider);
      await tester.ensureVisible(slider);
      await tester.drag(slider, const Offset(-2000, 0));
      await tester.pump();
      expect(container.read(settingsProvider).backgroundDim, 0);
    });

    testWidgets('an unreadable picture shows a message and changes nothing', (
      tester,
    ) async {
      final container = await _openSettings(
        tester,
        _PickerPlatform(fail: true),
      );
      final swatch = find.byKey(const ValueKey('background.image'));
      await tester.ensureVisible(swatch);
      await tester.tap(swatch);
      await tester.pump();
      await tester.pump();

      expect(find.text('That picture could not be used'), findsOneWidget);
      expect(
        container.read(settingsProvider).background,
        BackgroundStyle.aurora,
      );
    });

    testWidgets('a cancelled pick changes nothing', (tester) async {
      final container = await _openSettings(tester, _PickerPlatform());
      final swatch = find.byKey(const ValueKey('background.image'));
      await tester.ensureVisible(swatch);
      await tester.tap(swatch);
      await tester.pump();
      await tester.pump();
      expect(
        container.read(settingsProvider).background,
        BackgroundStyle.aurora,
      );
    });
  });
}
