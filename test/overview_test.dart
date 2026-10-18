import 'package:flutter/material.dart';
import 'package:flutter_application/app.dart';
import 'package:flutter_application/core/providers.dart';
import 'package:flutter_application/data/models/cellular_event.dart';
import 'package:flutter_application/data/models/cellular_info.dart';
import 'package:flutter_application/data/models/gnss_info.dart';
import 'package:flutter_application/data/models/sim_info.dart';
import 'package:flutter_application/data/models/wifi_info.dart';
import 'package:flutter_application/data/platform/unsupported_platform.dart';
import 'package:flutter_application/features/settings/domain/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Widget _app(FakeAndroidPlatform p) => ProviderScope(
      overrides: [
        signalPlatformProvider.overrideWithValue(p),
        initialSettingsProvider.overrideWithValue(const AppSettings(languageCode: 'en', updateIntervalMs: 500)),
      ],
      child: const SignalScopeApp(),
    );

Future<void> _unmount(WidgetTester tester) async {
  // Disposes providers so throttle timers and stream subscriptions are released.
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('overview shows each SIM independently plus Wi-Fi and GNSS', (tester) async {
    // The page is a lazy list; a tall surface makes every card build.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final p = FakeAndroidPlatform()
      ..sims = const [
        SimInfo(subscriptionId: 1, slotIndex: 0, carrierName: 'Alpha'),
        SimInfo(subscriptionId: 2, slotIndex: 1, carrierName: 'Beta', isDefaultData: true),
      ];
    await tester.pumpWidget(_app(p));
    await tester.pump(const Duration(milliseconds: 100));

    expect(p.cellularListens, 1);
    expect(p.lastSubscriptionIds, [1, 2]);
    expect(p.wifiListens, 1);
    expect(p.gnssListens, 1);

    // Nothing reported yet -> placeholders, not zeros.
    expect(find.text('SIM1 · Alpha'), findsOneWidget);
    expect(find.text('SIM2 · Beta'), findsOneWidget);
    expect(find.text('0'), findsNothing);

    p.cellularController
      ..add(const CellularSnapshotEvent(CellularInfo(
        subscriptionId: 1,
        timestampMs: 1000,
        dataNetworkType: 13,
        primaryRat: 'LTE',
        primaryDbm: -95,
      )))
      ..add(const CellularSnapshotEvent(CellularInfo(
        subscriptionId: 2,
        timestampMs: 1000,
        dataNetworkType: 3,
        primaryRat: 'WCDMA',
        primaryDbm: -80,
      )));
    p.wifiController.add(const WifiConnectionInfo(
      timestampMs: 1000,
      wifiEnabled: true,
      connected: true,
      ssid: 'Home',
      rssi: -55,
      frequencyMhz: 5180,
    ));
    p.gnssController.add(const GnssSnapshot(
      gnssSupported: true,
      timestampMs: 100000,
      satellites: [
        SatelliteInfo(svid: 1, constellation: Constellation.gps, cn0DbHz: 40, usedInFix: true),
        SatelliteInfo(svid: 2, constellation: Constellation.gps, cn0DbHz: 20, usedInFix: false),
      ],
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));

    // Chart axes also print numbers, so look inside each card.
    Finder inCard(String title, String text) => find.descendant(
          of: find.ancestor(of: find.text(title), matching: find.byType(Card)),
          matching: find.text(text),
        );
    expect(inCard('SIM1 · Alpha', '-95'), findsOneWidget);
    expect(inCard('SIM2 · Beta', '-80'), findsOneWidget);
    expect(inCard('SIM1 · Alpha', '-80'), findsNothing); // SIM2's value never leaks into SIM1
    expect(inCard('Wi-Fi', '-55'), findsOneWidget);
    expect(find.text('1 used / 2 visible'), findsOneWidget);
    expect(find.text('Searching'), findsOneWidget); // satellites but no position yet

    await _unmount(tester);
  });

  testWidgets('all native listeners are released in the background and restored on resume', (tester) async {
    final p = FakeAndroidPlatform()
      ..sims = const [SimInfo(subscriptionId: 1, slotIndex: 0, carrierName: 'Alpha')];
    await tester.pumpWidget(_app(p));
    await tester.pump(const Duration(milliseconds: 100));
    expect((p.cellularListens, p.wifiListens, p.gnssListens), (1, 1, 1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 100));
    expect((p.cellularCancels, p.wifiCancels, p.gnssCancels), (1, 1, 1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 100));
    expect((p.cellularListens, p.wifiListens, p.gnssListens), (2, 2, 2));

    await _unmount(tester);
  });

  testWidgets('overview on a device without SIM says so', (tester) async {
    final p = FakeAndroidPlatform();
    await tester.pumpWidget(_app(p));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('No SIM card detected'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('overview on an unsupported platform shows the notice', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [signalPlatformProvider.overrideWithValue(UnsupportedPlatform('windows'))],
      child: const SignalScopeApp(),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Not supported on this platform'), findsOneWidget);
    await _unmount(tester);
  });
}
