import 'package:flutter/material.dart';
import 'package:flutter_application/app.dart';
import 'package:flutter_application/core/providers.dart';
import 'package:flutter_application/data/models/cellular_event.dart';
import 'package:flutter_application/data/models/cellular_info.dart';
import 'package:flutter_application/data/models/sim_info.dart';
import 'package:flutter_application/data/models/wifi_info.dart';
import 'package:flutter_application/features/settings/domain/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('address fields', () {
    test('Wi-Fi: IPv6 lists and MAC are parsed; a missing MAC stays null', () {
      final w = WifiConnectionInfo.fromMap({
        'connected': true,
        'ipAddress': '192.168.1.5',
        'ipv6': ['2001:db8::5'],
        'ipv6LinkLocal': ['fe80::5'],
        'bssid': 'aa:bb:cc:dd:ee:ff',
      });
      expect(w.ipAddress, '192.168.1.5');
      expect(w.ipv6, ['2001:db8::5']);
      expect(w.ipv6LinkLocal, ['fe80::5']);
      expect(w.macAddress, isNull);
      expect(w.toMap()['deviceMac'], isNull);
      expect(w.toMap()['routerBssid'], 'aa:bb:cc:dd:ee:ff');
      expect(
        WifiConnectionInfo.fromMap({'macAddress': 'a4:b1:c2:00:11:22'})
            .macAddress,
        'a4:b1:c2:00:11:22',
      );
    });

    test(
      'cellular: data network flag and addresses; absent flag means unknown',
      () {
        final withNet = CellularInfo.fromMap({
          'subscriptionId': 1,
          'hasDataNetwork': true,
          'ipv4': '10.1.2.3',
          'ipv6': ['2001:db8::1', '2001:db8::2'],
        });
        expect(withNet.hasDataNetwork, isTrue);
        expect(withNet.ipv4, '10.1.2.3');
        expect(withNet.ipv6.length, 2);

        final noNet = CellularInfo.fromMap({
          'subscriptionId': 2,
          'hasDataNetwork': false,
        });
        expect(noNet.hasDataNetwork, isFalse);
        expect(noNet.ipv4, isNull);
        expect(noNet.ipv6, isEmpty);

        final old = CellularInfo.fromMap({'subscriptionId': 3});
        expect(old.hasDataNetwork, isNull);
        expect(old.toMap()['ipv4'], isNull);
      },
    );
  });

  testWidgets(
    'overview shows addresses per SIM and Wi-Fi without inventing a MAC',
    (tester) async {
      tester.view.physicalSize = const Size(800, 3600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final p = FakeAndroidPlatform()
        ..sims = const [
          SimInfo(
            subscriptionId: 1,
            slotIndex: 0,
            carrierName: 'Alpha',
            isDefaultData: true,
          ),
          SimInfo(subscriptionId: 2, slotIndex: 1, carrierName: 'Beta'),
        ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            signalPlatformProvider.overrideWithValue(p),
            initialSettingsProvider.overrideWithValue(
              const AppSettings(languageCode: 'en', updateIntervalMs: 500),
            ),
          ],
          child: const SignalScopeApp(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      p.cellularController
        ..add(
          CellularSnapshotEvent(
            CellularInfo.fromMap({
              'subscriptionId': 1,
              'hasDataNetwork': true,
              'ipv4': '10.1.2.3',
              'ipv6': ['2001:db8::1', '2001:db8::2'],
              'primaryRat': 'LTE',
              'primaryDbm': -90,
            }),
          ),
        )
        ..add(
          CellularSnapshotEvent(
            CellularInfo.fromMap({
              'subscriptionId': 2,
              'hasDataNetwork': false,
              'primaryRat': 'LTE',
              'primaryDbm': -100,
            }),
          ),
        );
      p.wifiController.add(
        WifiConnectionInfo.fromMap({
          'wifiEnabled': true,
          'connected': true,
          'ssid': 'Home',
          'bssid': 'aa:bb:cc:dd:ee:ff',
          'rssi': -55,
          'ipAddress': '192.168.1.5',
          'ipv6': ['2001:db8:5::5'],
        }),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('10.1.2.3'), findsOneWidget);
      expect(find.text('2001:db8::1  (+1)'), findsOneWidget);
      expect(find.text('No data connection on this SIM'), findsOneWidget);
      expect(find.text('192.168.1.5'), findsOneWidget);
      expect(find.text('2001:db8:5::5'), findsOneWidget);
      expect(find.text('Hidden by Android'), findsOneWidget);
      expect(find.text('aa:bb:cc:dd:ee:ff'), findsOneWidget);
      expect(find.text('02:00:00:00:00:00'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
