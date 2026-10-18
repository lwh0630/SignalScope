import 'package:flutter/widgets.dart';

import 'strings_en.dart';
import 'strings_zh.dart';

/// Lightweight bilingual string lookup (Simplified Chinese / English).
class AppStrings {
  AppStrings(this.locale);

  final Locale locale;

  bool get isZh => locale.languageCode == 'zh';

  Map<String, String> get _table => isZh ? stringsZh : stringsEn;

  String t(String key, [List<Object?> args = const []]) {
    var s = _table[key] ?? stringsEn[key] ?? key;
    for (var i = 0; i < args.length; i++) {
      s = s.replaceAll('{$i}', '${args[i]}');
    }
    return s;
  }

  static AppStrings of(BuildContext context) =>
      AppStrings(Localizations.localeOf(context));
}

extension TrContext on BuildContext {
  /// Translate [key] using the current locale.
  String tr(String key, [List<Object?> args = const []]) =>
      AppStrings.of(this).t(key, args);
}
