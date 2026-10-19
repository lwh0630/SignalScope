import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/utils/app_version.dart';
import '../../../data/models/app_update_info.dart';
import '../data/update_repository.dart';

final updateRepositoryProvider = Provider<UpdateRepository>(
  (ref) => UpdateRepository(),
);

/// Epoch milliseconds "now"; overridden in tests.
final updateClockProvider = Provider<int Function()>(
  (ref) =>
      () => DateTime.now().millisecondsSinceEpoch,
);

enum UpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,

  /// The system installer was opened; the user confirms there.
  installStarted,

  /// "Install unknown apps" must be allowed for SignalScope first.
  needPermission,
  error,
}

class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.current,
    this.release,
    this.progress,
    this.errorCode,
    this.pendingPrompt,
  });

  final UpdatePhase phase;

  /// Installed version, once known.
  final AppBuildInfo? current;

  /// Newest release when [phase] is `available` or later in the update flow.
  final ReleaseInfo? release;

  /// Download progress 0..1; `null` while unknown.
  final double? progress;

  /// Suffix of the `update.err.<code>` string.
  final String? errorCode;

  /// Set after a background check found an update; the UI shows a dialog once
  /// and calls [UpdateController.consumePrompt].
  final ReleaseInfo? pendingPrompt;

  bool get busy =>
      phase == UpdatePhase.checking || phase == UpdatePhase.downloading;

  UpdateState copyWith({
    UpdatePhase? phase,
    Object? current = _keep,
    Object? release = _keep,
    Object? progress = _keep,
    Object? errorCode = _keep,
    Object? pendingPrompt = _keep,
  }) => UpdateState(
    phase: phase ?? this.phase,
    current: identical(current, _keep)
        ? this.current
        : current as AppBuildInfo?,
    release: identical(release, _keep) ? this.release : release as ReleaseInfo?,
    progress: identical(progress, _keep) ? this.progress : progress as double?,
    errorCode: identical(errorCode, _keep)
        ? this.errorCode
        : errorCode as String?,
    pendingPrompt: identical(pendingPrompt, _keep)
        ? this.pendingPrompt
        : pendingPrompt as ReleaseInfo?,
  );
}

const Object _keep = Object();

/// Checks GitHub Releases, downloads the matching APK and hands it to the
/// system installer. Network access happens only here, after the user taps
/// "Check" / "Download", or in the once-a-day background check the user can
/// switch off in Settings.
class UpdateController extends Notifier<UpdateState> {
  /// Background checks run at most this often.
  static const Duration autoCheckInterval = Duration(hours: 24);

  UpdateCancel? _cancel;
  String? _apkPath;
  String? _sha256;
  bool _alive = true;

  @override
  UpdateState build() {
    _alive = true;
    ref.onDispose(() {
      _alive = false;
      _cancel?.cancel();
    });
    Future.microtask(() => autoCheckIfDue());
    return const UpdateState();
  }

  void _set(UpdateState s) {
    if (_alive) state = s;
  }

  /// Runs a silent check when the user allows it and the last one is old enough.
  Future<void> autoCheckIfDue() async {
    if (!_alive) return;
    final settings = ref.read(settingsProvider);
    if (!settings.autoCheckUpdates || state.busy) return;
    final now = ref.read(updateClockProvider)();
    final last = settings.lastUpdateCheckMs;
    if (last != null &&
        now - last >= 0 &&
        now - last < autoCheckInterval.inMilliseconds) {
      return;
    }
    await check(silent: true);
  }

  /// Looks for a newer release. [silent] checks never show an error and, when
  /// they find an update, request the prompt dialog.
  Future<void> check({bool silent = false}) async {
    if (state.busy) return;
    final platform = ref.read(signalPlatformProvider);
    final info = await platform.getAppBuildInfo();
    if (!_alive) return;
    if (info == null) {
      // Not an Android build: nothing to compare against.
      if (!silent) {
        _set(
          state.copyWith(phase: UpdatePhase.error, errorCode: 'unsupported'),
        );
      }
      return;
    }
    final installed = AppVersion.tryParse(info.versionName);
    if (installed == null) {
      if (!silent) {
        _set(
          state.copyWith(
            phase: UpdatePhase.error,
            current: info,
            errorCode: 'bad_version',
          ),
        );
      }
      return;
    }

    final previous = state.phase;
    _set(
      state.copyWith(
        phase: UpdatePhase.checking,
        current: info,
        errorCode: null,
        progress: null,
      ),
    );
    try {
      final release = await ref
          .read(updateRepositoryProvider)
          .fetchLatest(userAgent: 'SignalScope/${info.versionName}');
      if (!_alive) return;
      ref
          .read(settingsProvider.notifier)
          .update(
            (s) =>
                s.copyWith(lastUpdateCheckMs: ref.read(updateClockProvider)()),
          );
      if (release != null && release.version > installed) {
        _set(
          state.copyWith(
            phase: UpdatePhase.available,
            release: release,
            pendingPrompt: silent ? release : null,
          ),
        );
      } else {
        _set(state.copyWith(phase: UpdatePhase.upToDate, release: null));
      }
    } on UpdateException catch (e) {
      if (!_alive) return;
      _set(
        silent
            ? state.copyWith(phase: _quietPhase(previous))
            : state.copyWith(phase: UpdatePhase.error, errorCode: e.code),
      );
    }
  }

  /// A failed background check leaves the card as it was.
  UpdatePhase _quietPhase(UpdatePhase previous) =>
      previous == UpdatePhase.checking ? UpdatePhase.idle : previous;

  void consumePrompt() => _set(state.copyWith(pendingPrompt: null));

  /// Downloads the APK for this device and opens the system installer.
  Future<void> downloadAndInstall() async {
    final release = state.release;
    final info = state.current;
    if (state.busy || release == null || info == null) return;
    final platform = ref.read(signalPlatformProvider);
    final repo = ref.read(updateRepositoryProvider);
    final userAgent = 'SignalScope/${info.versionName}';

    final asset = UpdateRepository.pickApk(release, info.supportedAbis);
    if (asset == null) {
      _fail('no_asset');
      return;
    }
    final cancel = _cancel = UpdateCancel();
    _apkPath = null;
    _sha256 = null;
    _set(
      state.copyWith(
        phase: UpdatePhase.downloading,
        progress: null,
        errorCode: null,
      ),
    );
    try {
      final sha256 = await repo.fetchSha256(
        release,
        asset.name,
        userAgent: userAgent,
      );
      final dir = await platform.prepareUpdateDir();
      if (dir == null) {
        _fail('install');
        return;
      }
      final file = File('$dir${Platform.pathSeparator}update.apk');
      await repo.download(
        asset,
        file,
        userAgent: userAgent,
        cancel: cancel,
        onProgress: (received, total) {
          if (!_alive) return;
          _set(
            state.copyWith(
              progress: total == null || total <= 0
                  ? null
                  : (received / total).clamp(0.0, 1.0),
            ),
          );
        },
      );
      if (!_alive) return;
      _apkPath = file.path;
      _sha256 = sha256;
      await _install();
    } on UpdateException catch (e) {
      if (!_alive) return;
      if (e.code == 'cancelled') {
        _set(state.copyWith(phase: UpdatePhase.available, progress: null));
      } else {
        _fail(e.code);
      }
    } on Object {
      if (_alive) _fail('download');
    }
  }

  /// Retries the install of the file that is already downloaded (e.g. after the
  /// user allowed "install unknown apps").
  Future<void> installDownloaded() async {
    if (state.busy || _apkPath == null) return;
    await _install();
  }

  Future<void> _install() async {
    final path = _apkPath;
    final sha = _sha256;
    if (path == null || sha == null) return;
    final result = await ref.read(signalPlatformProvider).installApk(path, sha);
    if (!_alive) return;
    switch (result) {
      case InstallApkResult.started:
        _set(state.copyWith(phase: UpdatePhase.installStarted, progress: null));
      case InstallApkResult.needPermission:
        _set(state.copyWith(phase: UpdatePhase.needPermission, progress: null));
      case InstallApkResult.hashMismatch:
        await _forgetFile();
        _fail('hash');
      case InstallApkResult.signatureMismatch:
        await _forgetFile();
        _fail('signature');
      case InstallApkResult.notNewer:
        await _forgetFile();
        _fail('not_newer');
      case InstallApkResult.badApk:
        await _forgetFile();
        _fail('bad_apk');
      case InstallApkResult.failed:
        _fail('install');
    }
  }

  Future<void> _forgetFile() async {
    final path = _apkPath;
    _apkPath = null;
    _sha256 = null;
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } on Object {
      // Best effort: the directory is emptied before the next download anyway.
    }
  }

  void _fail(String code) => _set(
    state.copyWith(phase: UpdatePhase.error, errorCode: code, progress: null),
  );

  /// Stops a running download.
  void cancelDownload() => _cancel?.cancel();

  Future<void> openInstallPermissionSettings() =>
      ref.read(signalPlatformProvider).openInstallPermissionSettings();
}

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);
