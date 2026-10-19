import 'model_utils.dart';

/// Installed app version and device ABIs, as reported by `PackageManager` / `Build`.
class AppBuildInfo {
  const AppBuildInfo({
    required this.versionName,
    this.versionCode,
    this.supportedAbis = const [],
  });

  /// `versionName` of the installed app (the release tag without the leading `v`).
  final String versionName;
  final int? versionCode;

  /// `Build.SUPPORTED_ABIS`, most preferred first.
  final List<String> supportedAbis;

  static AppBuildInfo? fromMap(Map<Object?, Object?>? m) {
    final name = asString(m?['versionName']);
    if (m == null || name == null || name.isEmpty) return null;
    return AppBuildInfo(
      versionName: name,
      versionCode: asInt(m['versionCode']),
      supportedAbis: asStringList(m['supportedAbis']),
    );
  }
}

/// Outcome of handing a downloaded APK to the system installer.
enum InstallApkResult {
  /// The system installer was opened; the user confirms there.
  started('started'),

  /// "Install unknown apps" is not allowed for SignalScope yet.
  needPermission('need_permission'),

  /// The file's SHA-256 differs from the published checksum.
  hashMismatch('hash_mismatch'),

  /// The APK is not signed with the key of the installed app.
  signatureMismatch('signature_mismatch'),

  /// The APK is not newer than the installed version.
  notNewer('not_newer'),

  /// Not a valid SignalScope APK.
  badApk('bad_apk'),

  /// Anything else, or the platform cannot install.
  failed('failed');

  const InstallApkResult(this.code);
  final String code;

  static InstallApkResult fromCode(String? code) {
    for (final r in InstallApkResult.values) {
      if (r.code == code) return r;
    }
    return InstallApkResult.failed;
  }
}
