import 'package:flutter/services.dart';
import 'package:flutter_application/data/models/platform_info.dart';
import 'package:flutter_application/data/platform/android_platform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('signalscope/method');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

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
    messenger.setMockMethodCallHandler(channel, (call) async => {
          'location': 'granted',
          'phone': 'permanentlyDenied',
          'nearbyWifi': 'notApplicable',
          'locationServicesEnabled': false,
        });
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
    final p = await AndroidPlatform().requestPermissions({PermGroup.location, PermGroup.phone});
    expect((sent as Map)['groups'], containsAll(['location', 'phone']));
    expect(p.phone, PermStatus.granted);
  });

  test('native failure degrades to empty data, not exceptions', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'native_error');
    });
    expect(await AndroidPlatform().getSimList(), isEmpty);
    expect(await AndroidPlatform().getWifiConnection(), isNull);
  });
}
