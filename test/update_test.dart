import 'dart:convert';
import 'dart:io';

import 'package:flutter_application/core/app_info.dart';
import 'package:flutter_application/core/providers.dart';
import 'package:flutter_application/core/utils/app_version.dart';
import 'package:flutter_application/data/models/app_update_info.dart';
import 'package:flutter_application/features/settings/domain/app_settings.dart';
import 'package:flutter_application/features/update/application/update_controller.dart';
import 'package:flutter_application/features/update/data/update_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

final _hash = 'a' * 64;

/// Local stand-in for GitHub: API JSON, a redirecting asset URL and the checksum file.
class _FakeGitHub {
  late HttpServer server;
  int apiStatus = 200;
  String tag = 'v1.2.0';
  bool prerelease = false;
  bool includeChecksum = true;
  List<int> apk = List<int>.generate(50000, (i) => i % 251);
  int? truncateTo;
  final requests = <String>[];
  final userAgents = <String?>[];

  String get base => 'http://127.0.0.1:${server.port}';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      requests.add(req.uri.path);
      userAgents.add(req.headers.value(HttpHeaders.userAgentHeader));
      final res = req.response;
      switch (req.uri.path) {
        case '/latest':
          res.statusCode = apiStatus;
          res.write(
            jsonEncode({
              'tag_name': tag,
              'draft': false,
              'prerelease': prerelease,
              'body': 'Notes for $tag',
              'assets': [
                for (final abi in ['arm64-v8a', 'x86_64'])
                  {
                    'name': 'signalscope-$tag-$abi.apk',
                    'browser_download_url':
                        '$base/dl/signalscope-$tag-$abi.apk',
                    'size': apk.length,
                  },
                if (includeChecksum)
                  {
                    'name': 'SHA256SUMS.txt',
                    'browser_download_url': '$base/dl/SHA256SUMS.txt',
                    'size': 100,
                  },
              ],
            }),
          );
        case final p when p.startsWith('/dl/SHA256SUMS'):
          res.write(
            '$_hash  signalscope-$tag-arm64-v8a.apk\n'
            '${'b' * 64} *signalscope-$tag-x86_64.apk\n',
          );
        case final p when p.startsWith('/dl/'):
          // Like GitHub: the asset URL redirects to a CDN URL.
          res.statusCode = HttpStatus.found;
          res.headers.set(HttpHeaders.locationHeader, '/blob${p.substring(3)}');
        case final p when p.startsWith('/blob/'):
          final body = truncateTo == null ? apk : apk.sublist(0, truncateTo!);
          res.contentLength = apk.length;
          res.add(body);
        case '/evil':
          res.statusCode = HttpStatus.found;
          res.headers.set(
            HttpHeaders.locationHeader,
            'http://example.invalid/steal.apk',
          );
        default:
          res.statusCode = HttpStatus.notFound;
      }
      try {
        await res.close();
      } on Object {
        // Truncated body: the client may already have hung up.
      }
    });
  }

  Future<void> stop() => server.close(force: true);

  UpdateRepository repo({String latestPath = '/latest'}) => UpdateRepository(
    latestReleaseUrl: Uri.parse('$base$latestPath'),
    urlPolicy: (u) => u.scheme == 'http' && u.host == '127.0.0.1',
    requestTimeout: const Duration(seconds: 3),
    idleTimeout: const Duration(seconds: 3),
  );
}

class _UpdatePlatform extends FakeAndroidPlatform {
  _UpdatePlatform(this.dir);

  final Directory dir;
  AppBuildInfo? build = const AppBuildInfo(
    versionName: '1.0.0',
    versionCode: 4001,
    supportedAbis: ['arm64-v8a', 'armeabi-v7a'],
  );
  InstallApkResult installResult = InstallApkResult.started;
  final installs = <(String, String)>[];
  int permissionSettingsOpened = 0;
  int dirPrepared = 0;

  @override
  Future<AppBuildInfo?> getAppBuildInfo() async => build;

  @override
  Future<String?> prepareUpdateDir() async {
    dirPrepared++;
    return dir.path;
  }

  @override
  Future<InstallApkResult> installApk(String path, String sha256) async {
    installs.add((path, sha256));
    return installResult;
  }

  @override
  Future<bool> openInstallPermissionSettings() async {
    permissionSettingsOpened++;
    return true;
  }
}

void main() {
  group('AppVersion', () {
    test('parses tags and versions, ignores v prefix and build metadata', () {
      expect(AppVersion.tryParse('v1.2.3').toString(), '1.2.3');
      expect(AppVersion.tryParse('1.2.3+45').toString(), '1.2.3');
      expect(AppVersion.tryParse('1.2.3-beta.1')!.isPreRelease, isTrue);
      expect(AppVersion.tryParse('1.2'), isNull);
      expect(AppVersion.tryParse('latest'), isNull);
      expect(AppVersion.tryParse(null), isNull);
    });

    test('orders numerically, not as text, and pre-release < release', () {
      AppVersion v(String s) => AppVersion.tryParse(s)!;
      expect(v('1.10.0') > v('1.9.9'), isTrue);
      expect(v('2.0.0') > v('1.99.99'), isTrue);
      expect(v('1.0.1') > v('1.0.0'), isTrue);
      expect(v('1.0.0') > v('1.0.0-rc.1'), isTrue);
      expect(v('1.0.0-rc.2') > v('1.0.0-rc.1'), isTrue);
      expect(v('1.0.0-rc.10') > v('1.0.0-rc.2'), isTrue);
      expect(v('1.0.0-beta') > v('1.0.0-alpha'), isTrue);
      expect(v('1.0.0') == v('v1.0.0'), isTrue);
      expect(v('1.0.0') > v('1.0.0'), isFalse);
    });
  });

  group('release parsing', () {
    Map<String, Object?> release({
      String tag = 'v1.2.0',
      bool draft = false,
      bool prerelease = false,
    }) => {
      'tag_name': tag,
      'draft': draft,
      'prerelease': prerelease,
      'body': '  What changed  ',
      'assets': [
        {
          'name': 'signalscope-v1.2.0-arm64-v8a.apk',
          'browser_download_url':
              'https://github.com/o/r/releases/download/v1.2.0/a.apk',
          'size': 10,
        },
        {
          'name': 'signalscope-v1.2.0-armeabi-v7a.apk',
          'browser_download_url':
              'https://github.com/o/r/releases/download/v1.2.0/b.apk',
        },
        {'name': 'broken'},
      ],
    };

    test('valid release', () {
      final r = UpdateRepository.parseRelease(release())!;
      expect(r.tag, 'v1.2.0');
      expect(r.version.toString(), '1.2.0');
      expect(r.notes, 'What changed');
      expect(r.assets, hasLength(2));
      expect(r.assets.first.size, 10);
    });

    test('drafts, pre-releases and non-version tags are never offered', () {
      expect(UpdateRepository.parseRelease(release(draft: true)), isNull);
      expect(UpdateRepository.parseRelease(release(prerelease: true)), isNull);
      expect(
        UpdateRepository.parseRelease(release(tag: 'v1.3.0-beta.1')),
        isNull,
      );
      expect(UpdateRepository.parseRelease(release(tag: 'nightly')), isNull);
      expect(UpdateRepository.parseRelease('nope'), isNull);
    });

    test('APK is chosen by the most preferred ABI the release contains', () {
      final r = UpdateRepository.parseRelease(release())!;
      expect(
        UpdateRepository.pickApk(r, ['arm64-v8a', 'armeabi-v7a'])!.name,
        endsWith('arm64-v8a.apk'),
      );
      expect(
        UpdateRepository.pickApk(r, ['x86_64', 'armeabi-v7a'])!.name,
        endsWith('armeabi-v7a.apk'),
      );
      expect(UpdateRepository.pickApk(r, ['x86_64']), isNull);
      expect(UpdateRepository.pickApk(r, const []), isNull);
    });

    test('sha256sum files are parsed (text and binary marker)', () {
      final m = UpdateRepository.parseChecksums(
        '${'A' * 64}  one.apk\r\n${'b' * 64} *two.apk\nnot a line\n${'c' * 63}  short.apk\n',
      );
      expect(m, {'one.apk': 'a' * 64, 'two.apk': 'b' * 64});
    });

    test('only HTTPS GitHub hosts are allowed by default', () {
      expect(githubOnlyPolicy(Uri.parse('https://api.github.com/x')), isTrue);
      expect(githubOnlyPolicy(Uri.parse('https://github.com/x')), isTrue);
      expect(
        githubOnlyPolicy(
          Uri.parse('https://release-assets.githubusercontent.com/x'),
        ),
        isTrue,
      );
      expect(githubOnlyPolicy(Uri.parse('http://github.com/x')), isFalse);
      expect(githubOnlyPolicy(Uri.parse('https://evilgithub.com/x')), isFalse);
      expect(
        githubOnlyPolicy(Uri.parse('https://github.com.evil.io/x')),
        isFalse,
      );
    });
  });

  group('UpdateRepository (local server)', () {
    late _FakeGitHub gh;
    late Directory tmp;

    setUp(() async {
      gh = _FakeGitHub();
      await gh.start();
      tmp = await Directory.systemTemp.createTemp('signalscope_update_test');
    });
    tearDown(() async {
      await gh.stop();
      await tmp.delete(recursive: true);
    });

    test(
      'fetchLatest reads the release and identifies the app version',
      () async {
        final r = await gh.repo().fetchLatest(userAgent: 'SignalScope/1.0.0');
        expect(r!.tag, 'v1.2.0');
        expect(r.assets.map((a) => a.name), contains('SHA256SUMS.txt'));
        expect(gh.userAgents.single, 'SignalScope/1.0.0');
      },
    );

    test(
      '404 means "no release", 403 means rate limit, junk is rejected',
      () async {
        expect(
          await gh.repo(latestPath: '/none').fetchLatest(userAgent: 'x'),
          isNull,
        );

        gh.apiStatus = 403;
        await expectLater(
          gh.repo().fetchLatest(userAgent: 'x'),
          throwsA(
            isA<UpdateException>().having((e) => e.code, 'code', 'rate_limit'),
          ),
        );
        gh.apiStatus = 500;
        await expectLater(
          gh.repo().fetchLatest(userAgent: 'x'),
          throwsA(
            isA<UpdateException>().having(
              (e) => e.code,
              'code',
              'bad_response',
            ),
          ),
        );
      },
    );

    test('an unreachable server is a network error', () async {
      final repo = gh.repo();
      await gh.stop();
      await expectLater(
        repo.fetchLatest(userAgent: 'x'),
        throwsA(
          isA<UpdateException>().having((e) => e.code, 'code', 'network'),
        ),
      );
      // tearDown stops it again; restart so close() has something to close.
      await gh.start();
    });

    test(
      'checksum is looked up by APK name; missing file or entry fails',
      () async {
        final repo = gh.repo();
        final r = (await repo.fetchLatest(userAgent: 'x'))!;
        expect(
          await repo.fetchSha256(
            r,
            'signalscope-v1.2.0-arm64-v8a.apk',
            userAgent: 'x',
          ),
          _hash,
        );
        await expectLater(
          repo.fetchSha256(
            r,
            'signalscope-v1.2.0-armeabi-v7a.apk',
            userAgent: 'x',
          ),
          throwsA(
            isA<UpdateException>().having((e) => e.code, 'code', 'no_checksum'),
          ),
        );

        gh.includeChecksum = false;
        final noSums = (await repo.fetchLatest(userAgent: 'x'))!;
        await expectLater(
          repo.fetchSha256(
            noSums,
            'signalscope-v1.2.0-arm64-v8a.apk',
            userAgent: 'x',
          ),
          throwsA(
            isA<UpdateException>().having((e) => e.code, 'code', 'no_checksum'),
          ),
        );
      },
    );

    test('download follows the redirect and reports progress', () async {
      final repo = gh.repo();
      final r = (await repo.fetchLatest(userAgent: 'x'))!;
      final asset = UpdateRepository.pickApk(r, ['arm64-v8a'])!;
      final file = File('${tmp.path}/update.apk');
      final progress = <int>[];
      await repo.download(
        asset,
        file,
        userAgent: 'x',
        onProgress: (received, total) {
          progress.add(received);
          expect(total, gh.apk.length);
        },
      );
      expect(await file.readAsBytes(), gh.apk);
      expect(progress.last, gh.apk.length);
      expect(gh.requests, contains('/blob/signalscope-v1.2.0-arm64-v8a.apk'));
    });

    test('incomplete download is an error and leaves no file', () async {
      final repo = gh.repo();
      final r = (await repo.fetchLatest(userAgent: 'x'))!;
      final asset = UpdateRepository.pickApk(r, ['arm64-v8a'])!;
      gh.truncateTo = 1000;
      final file = File('${tmp.path}/update.apk');
      await expectLater(
        repo.download(asset, file, userAgent: 'x'),
        throwsA(isA<UpdateException>()),
      );
      expect(await file.exists(), isFalse);
    });

    test('cancel stops the download and removes the partial file', () async {
      final repo = gh.repo();
      final r = (await repo.fetchLatest(userAgent: 'x'))!;
      final asset = UpdateRepository.pickApk(r, ['arm64-v8a'])!;
      final cancel = UpdateCancel();
      final file = File('${tmp.path}/update.apk');
      await expectLater(
        repo.download(
          asset,
          file,
          userAgent: 'x',
          cancel: cancel,
          onProgress: (_, _) => cancel.cancel(),
        ),
        throwsA(
          isA<UpdateException>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      expect(await file.exists(), isFalse);
    });

    test('a redirect to a host outside the policy is refused', () async {
      final repo = gh.repo();
      final asset = ReleaseAsset(
        name: 'x.apk',
        url: Uri.parse('${gh.base}/evil'),
      );
      await expectLater(
        repo.download(asset, File('${tmp.path}/update.apk'), userAgent: 'x'),
        throwsA(
          isA<UpdateException>().having((e) => e.code, 'code', 'bad_url'),
        ),
      );
    });

    test('the production policy refuses a plain-HTTP API URL', () async {
      final repo = UpdateRepository(
        latestReleaseUrl: Uri.parse('${gh.base}/latest'),
      );
      await expectLater(
        repo.fetchLatest(userAgent: 'x'),
        throwsA(
          isA<UpdateException>().having((e) => e.code, 'code', 'bad_url'),
        ),
      );
      expect(gh.requests, isEmpty);
    });
  });

  group('UpdateController', () {
    late _FakeGitHub gh;
    late Directory tmp;
    late _UpdatePlatform platform;

    setUp(() async {
      gh = _FakeGitHub();
      await gh.start();
      tmp = await Directory.systemTemp.createTemp('signalscope_update_test');
      platform = _UpdatePlatform(tmp);
    });
    tearDown(() async {
      await gh.stop();
      await tmp.delete(recursive: true);
    });

    const day = 24 * 60 * 60 * 1000;
    const t0 = 1000 * day;

    ProviderContainer container({AppSettings? settings}) {
      final c = ProviderContainer(
        overrides: [
          updateClockProvider.overrideWithValue(() => t0),
          signalPlatformProvider.overrideWithValue(platform),
          initialSettingsProvider.overrideWithValue(
            settings ?? const AppSettings(autoCheckUpdates: false),
          ),
          updateRepositoryProvider.overrideWithValue(gh.repo()),
        ],
      );
      addTearDown(c.dispose);
      c.listen(updateControllerProvider, (_, _) {});
      return c;
    }

    test(
      'manual check finds a newer release, no prompt for manual checks',
      () async {
        final c = container();
        await c.read(updateControllerProvider.notifier).check();
        final s = c.read(updateControllerProvider);
        expect(s.phase, UpdatePhase.available);
        expect(s.release!.tag, 'v1.2.0');
        expect(s.pendingPrompt, isNull);
        expect(c.read(settingsProvider).lastUpdateCheckMs, isNotNull);
      },
    );

    test('same or older release means up to date', () async {
      final c = container();
      gh.tag = 'v1.0.0';
      await c.read(updateControllerProvider.notifier).check();
      expect(c.read(updateControllerProvider).phase, UpdatePhase.upToDate);
      gh.tag = 'v0.9.0';
      await c.read(updateControllerProvider.notifier).check();
      expect(c.read(updateControllerProvider).phase, UpdatePhase.upToDate);
    });

    test('pre-releases are ignored', () async {
      final c = container();
      gh.prerelease = true;
      await c.read(updateControllerProvider.notifier).check();
      expect(c.read(updateControllerProvider).phase, UpdatePhase.upToDate);
    });

    test('manual error is shown, silent error is not', () async {
      final c = container();
      gh.apiStatus = 403;
      await c.read(updateControllerProvider.notifier).check(silent: true);
      expect(c.read(updateControllerProvider).phase, UpdatePhase.idle);
      expect(c.read(updateControllerProvider).errorCode, isNull);
      // A failed check is not recorded as done, so the next launch retries.
      expect(c.read(settingsProvider).lastUpdateCheckMs, isNull);

      await c.read(updateControllerProvider.notifier).check();
      expect(c.read(updateControllerProvider).phase, UpdatePhase.error);
      expect(c.read(updateControllerProvider).errorCode, 'rate_limit');
    });

    test(
      'unknown platform version: manual error, silent nothing, no request',
      () async {
        final c = container();
        platform.build = null;
        await c.read(updateControllerProvider.notifier).check(silent: true);
        expect(c.read(updateControllerProvider).phase, UpdatePhase.idle);
        await c.read(updateControllerProvider.notifier).check();
        expect(c.read(updateControllerProvider).errorCode, 'unsupported');
        expect(gh.requests, isEmpty);
      },
    );

    test(
      'background check: only when enabled and at most once per 24 h',
      () async {
        // The controller starts the background check by itself when it is created.
        Future<void> settle(ProviderContainer c) async {
          await pumpEventQueue();
          for (
            var i = 0;
            i < 100 && c.read(updateControllerProvider).busy;
            i++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }

        var c = container(settings: const AppSettings(autoCheckUpdates: false));
        await settle(c);
        expect(gh.requests, isEmpty);

        c = container(
          settings: const AppSettings(lastUpdateCheckMs: t0 - day ~/ 2),
        );
        await settle(c);
        expect(gh.requests, isEmpty);

        c = container(settings: const AppSettings(lastUpdateCheckMs: t0 - day));
        await settle(c);
        expect(gh.requests, ['/latest']);
        expect(c.read(settingsProvider).lastUpdateCheckMs, t0);
        final s = c.read(updateControllerProvider);
        expect(s.phase, UpdatePhase.available);
        expect(s.pendingPrompt!.tag, 'v1.2.0');

        c.read(updateControllerProvider.notifier).consumePrompt();
        expect(c.read(updateControllerProvider).pendingPrompt, isNull);
        expect(c.read(updateControllerProvider).phase, UpdatePhase.available);
      },
    );

    test(
      'download then install: sends the published hash to the installer',
      () async {
        final c = container();
        final n = c.read(updateControllerProvider.notifier);
        await n.check();
        await n.downloadAndInstall();

        expect(
          c.read(updateControllerProvider).phase,
          UpdatePhase.installStarted,
        );
        final (path, sha) = platform.installs.single;
        expect(sha, _hash);
        expect(path, startsWith(tmp.path));
        expect(await File(path).readAsBytes(), gh.apk);
        expect(platform.dirPrepared, 1);
      },
    );

    test(
      'hash / signature / version rejection deletes the file and reports why',
      () async {
        final expected = {
          InstallApkResult.hashMismatch: 'hash',
          InstallApkResult.signatureMismatch: 'signature',
          InstallApkResult.notNewer: 'not_newer',
          InstallApkResult.badApk: 'bad_apk',
        };
        for (final e in expected.entries) {
          final c = container();
          final n = c.read(updateControllerProvider.notifier);
          platform.installResult = e.key;
          await n.check();
          await n.downloadAndInstall();
          final s = c.read(updateControllerProvider);
          expect(s.phase, UpdatePhase.error, reason: '${e.key}');
          expect(s.errorCode, e.value);
          expect(await File('${tmp.path}/update.apk').exists(), isFalse);
        }
      },
    );

    test(
      'install permission: ask, then continue with the downloaded file',
      () async {
        final c = container();
        final n = c.read(updateControllerProvider.notifier);
        platform.installResult = InstallApkResult.needPermission;
        await n.check();
        await n.downloadAndInstall();
        expect(
          c.read(updateControllerProvider).phase,
          UpdatePhase.needPermission,
        );

        await n.openInstallPermissionSettings();
        expect(platform.permissionSettingsOpened, 1);

        platform.installResult = InstallApkResult.started;
        await n.installDownloaded();
        expect(
          c.read(updateControllerProvider).phase,
          UpdatePhase.installStarted,
        );
        expect(platform.installs, hasLength(2));
        expect(
          platform.dirPrepared,
          1,
          reason: 'the file is not downloaded again',
        );
      },
    );

    test('no APK for this device, or no checksum, is an error', () async {
      var c = container();
      platform.build = const AppBuildInfo(
        versionName: '1.0.0',
        supportedAbis: ['riscv64'],
      );
      await c.read(updateControllerProvider.notifier).check();
      await c.read(updateControllerProvider.notifier).downloadAndInstall();
      expect(c.read(updateControllerProvider).errorCode, 'no_asset');

      platform.build = const AppBuildInfo(
        versionName: '1.0.0',
        supportedAbis: ['arm64-v8a'],
      );
      gh.includeChecksum = false;
      c = container();
      await c.read(updateControllerProvider.notifier).check();
      await c.read(updateControllerProvider.notifier).downloadAndInstall();
      expect(c.read(updateControllerProvider).errorCode, 'no_checksum');
      expect(platform.installs, isEmpty);
    });

    test('a broken download never reaches the installer', () async {
      final c = container();
      final n = c.read(updateControllerProvider.notifier);
      await n.check();
      gh.truncateTo = 10;
      await n.downloadAndInstall();
      expect(c.read(updateControllerProvider).phase, UpdatePhase.error);
      expect(platform.installs, isEmpty);
    });

    test('cancelling returns to "available"', () async {
      final c = container();
      final n = c.read(updateControllerProvider.notifier);
      await n.check();
      final run = n.downloadAndInstall();
      n.cancelDownload();
      await run;
      expect(c.read(updateControllerProvider).phase, UpdatePhase.available);
      expect(platform.installs, isEmpty);
    });
  });

  group('installed version', () {
    test('comes from the system, not from the hard-coded fallback', () async {
      final dir = Directory.systemTemp;
      final platform = _UpdatePlatform(dir)
        ..build = const AppBuildInfo(versionName: '2.5.1');
      final c = ProviderContainer(
        overrides: [signalPlatformProvider.overrideWithValue(platform)],
      );
      addTearDown(c.dispose);
      expect(await c.read(installedVersionProvider.future), '2.5.1');
    });

    test('falls back to kAppVersion when the host cannot report it', () async {
      final platform = _UpdatePlatform(Directory.systemTemp)..build = null;
      final c = ProviderContainer(
        overrides: [signalPlatformProvider.overrideWithValue(platform)],
      );
      addTearDown(c.dispose);
      expect(await c.read(installedVersionProvider.future), kAppVersion);
    });
  });

  group('settings', () {
    test('auto-check defaults to on and survives a round trip', () {
      expect(const AppSettings().autoCheckUpdates, isTrue);
      expect(AppSettings.fromJson('{}').autoCheckUpdates, isTrue);
      expect(AppSettings.fromJson('{}').lastUpdateCheckMs, isNull);
      final s = const AppSettings(
        autoCheckUpdates: false,
        lastUpdateCheckMs: 123,
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.autoCheckUpdates, isFalse);
      expect(back.lastUpdateCheckMs, 123);
      expect(
        AppSettings.fromJson('{"autoCheckUpdates":"yes"}').autoCheckUpdates,
        isTrue,
      );
    });
  });
}
