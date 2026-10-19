import 'package:flutter/services.dart';
import 'package:flutter_application/data/models/app_update_info.dart';
import 'package:flutter_application/data/models/platform_info.dart';
import 'package:flutter_application/data/platform/android_platform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('signalscope/method');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('capabilities are parsed and unknown values stay null', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getCapabilities');
      return {
        'platform': 'android',
        'sdkInt': 34,
        'hasTelephony': true,
        'hasGnss': null,
      };
    });
    final caps = await AndroidPlatform().getCapabilities();
    expect(caps.sdkInt, 34);
    expect(caps.hasTelephony, true);
    expect(caps.hasGnss, isNull);
    expect(caps.simCount, isNull);
  });

  test('permission snapshot parses statuses', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => {
        'location': 'granted',
        'phone': 'permanentlyDenied',
        'nearbyWifi': 'notApplicable',
        'locationServicesEnabled': false,
      },
    );
    final p = await AndroidPlatform().getPermissions();
    expect(p.location, PermStatus.granted);
    expect(p.phone, PermStatus.permanentlyDenied);
    expect(p.nearbyWifi, PermStatus.notApplicable);
    expect(p.locationServicesEnabled, false);
  });

  test('requestPermissions sends group names', () async {
    Object? sent;
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent = call.arguments;
      return {'location': 'denied', 'phone': 'granted'};
    });
    final p = await AndroidPlatform().requestPermissions({
      PermGroup.location,
      PermGroup.phone,
    });
    expect((sent as Map)['groups'], containsAll(['location', 'phone']));
    expect(p.phone, PermStatus.granted);
  });

  test('app build info is parsed; missing version means unknown', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getAppBuildInfo');
      return {
        'versionName': '1.2.0',
        'versionCode': 4001,
        'supportedAbis': ['arm64-v8a', 'armeabi-v7a'],
      };
    });
    final info = await AndroidPlatform().getAppBuildInfo();
    expect(info!.versionName, '1.2.0');
    expect(info.versionCode, 4001);
    expect(info.supportedAbis, ['arm64-v8a', 'armeabi-v7a']);

    messenger.setMockMethodCallHandler(
      channel,
      (call) async => {'versionCode': 1},
    );
    expect(await AndroidPlatform().getAppBuildInfo(), isNull);
  });

  test('installApk sends path and hash and maps every native result', () async {
    Object? sent;
    String reply = 'started';
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'installApk');
      sent = call.arguments;
      return reply;
    });
    final p = AndroidPlatform();
    expect(
      await p.installApk('/c/updates/update.apk', 'ab'),
      InstallApkResult.started,
    );
    expect(sent, {'path': '/c/updates/update.apk', 'sha256': 'ab'});
    for (final r in InstallApkResult.values) {
      reply = r.code;
      expect(await p.installApk('/x', 'y'), r);
    }
    reply = 'something_new';
    expect(await p.installApk('/x', 'y'), InstallApkResult.failed);
  });

  test(
    'update directory and permission screen go through the channel',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'prepareUpdateDir':
            return '/cache/updates';
          case 'openInstallPermissionSettings':
            return true;
        }
        return null;
      });
      final p = AndroidPlatform();
      expect(await p.prepareUpdateDir(), '/cache/updates');
      expect(await p.openInstallPermissionSettings(), isTrue);

      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'native_error');
      });
      expect(await p.prepareUpdateDir(), isNull);
      expect(await p.installApk('/x', 'y'), InstallApkResult.failed);
      expect(await p.openInstallPermissionSettings(), isFalse);
    },
  );

  test('native failure degrades to empty data, not exceptions', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'native_error');
    });
    expect(await AndroidPlatform().getSimList(), isEmpty);
    expect(await AndroidPlatform().getWifiConnection(), isNull);
  });
}
