import 'dart:io';

import 'package:flutter_application/core/i18n/strings_en.dart';
import 'package:flutter_application/core/i18n/strings_zh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final placeholder = RegExp(r'\{(\d+)\}');

  Set<String> placeholders(String s) =>
      placeholder.allMatches(s).map((m) => m.group(1)!).toSet();

  test('Chinese and English tables have exactly the same keys', () {
    final onlyEn = stringsEn.keys.toSet().difference(stringsZh.keys.toSet());
    final onlyZh = stringsZh.keys.toSet().difference(stringsEn.keys.toSet());
    expect(onlyEn, isEmpty, reason: 'missing in zh: $onlyEn');
    expect(onlyZh, isEmpty, reason: 'missing in en: $onlyZh');
  });

  test('no empty strings and matching {n} placeholders', () {
    for (final k in stringsEn.keys) {
      expect(stringsEn[k], isNotEmpty, reason: 'en $k');
      expect(stringsZh[k], isNotEmpty, reason: 'zh $k');
      expect(
        placeholders(stringsZh[k]!),
        placeholders(stringsEn[k]!),
        reason: 'placeholders of $k',
      );
    }
  });

  test('every literal key used with context.tr(...) exists', () {
    final used = RegExp(r"""\btr\(\s*'([A-Za-z0-9_.]+)'""");
    final missing = <String>{};
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.contains('i18n')) continue;
      for (final m in used.allMatches(f.readAsStringSync())) {
        final key = m.group(1)!;
        if (!stringsEn.containsKey(key)) missing.add('$key (${f.path})');
      }
    }
    expect(missing, isEmpty);
  });

  test('reason codes sent by native code have a translation', () {
    // Codes produced in Kotlin (issues lists) and Dart repositories.
    const codes = {
      'issue': [
        'no_location_permission',
        'no_phone_permission',
        'cell_info_empty',
        'listener_failed',
        'callback_denied',
        'telephony_unavailable',
      ],
      'wifiissue': [
        'wifi_disabled',
        'wifi_unsupported',
        'no_location_permission',
        'location_off',
        'ssid_hidden',
        'platform_unsupported',
        'native_error',
      ],
      'gnssissue': [
        'gnss_unsupported',
        'no_location_permission',
        'location_off',
        'gps_provider_disabled',
        'platform_unsupported',
        'native_error',
        'fallback_unavailable',
      ],
    };
    for (final e in codes.entries) {
      for (final c in e.value) {
        expect(
          stringsEn.containsKey('${e.key}.$c'),
          isTrue,
          reason: '${e.key}.$c',
        );
        expect(
          stringsZh.containsKey('${e.key}.$c'),
          isTrue,
          reason: 'zh ${e.key}.$c',
        );
      }
    }
  });
}
