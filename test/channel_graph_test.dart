import 'package:flutter/material.dart';
import 'package:flutter_application/core/utils/wifi_utils.dart';
import 'package:flutter_application/data/models/wifi_info.dart';
import 'package:flutter_application/features/wifi/presentation/channel_geometry.dart';
import 'package:flutter_application/features/wifi/presentation/channel_graph.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChannelGeometry', () {
    test('channel centre frequencies', () {
      expect(ChannelGeometry.channelCenterMhz(WifiBand.ghz24, 1), 2412);
      expect(ChannelGeometry.channelCenterMhz(WifiBand.ghz24, 6), 2437);
      expect(ChannelGeometry.channelCenterMhz(WifiBand.ghz5, 36), 5180);
      expect(ChannelGeometry.channelCenterMhz(WifiBand.ghz6, 1), 5955);
    });

    test(
      '2.4 GHz 20 MHz access points occupy 22 MHz, other widths are exact',
      () {
        const a = WifiScanInfo(
          bssid: 'a',
          rssi: -50,
          frequencyMhz: 2437,
          channelWidthCode: 0,
        );
        expect(ChannelGeometry.occupiedWidthMhz(a), 22);
        expect(ChannelGeometry.span(a), (2426.0, 2448.0));
        const b = WifiScanInfo(
          bssid: 'b',
          rssi: -50,
          frequencyMhz: 5180,
          centerFreq0Mhz: 5210,
          channelWidthCode: 2,
        );
        expect(ChannelGeometry.span(b), (5170.0, 5250.0));
        // Unknown width falls back to 20 MHz.
        const c = WifiScanInfo(bssid: 'c', rssi: -50, frequencyMhz: 5745);
        expect(ChannelGeometry.span(c), (5735.0, 5755.0));
        expect(ChannelGeometry.span(const WifiScanInfo(bssid: 'd')), isNull);
      },
    );

    test('x and y fractions', () {
      expect(ChannelGeometry.xFraction(WifiBand.ghz24, 2400), 0);
      expect(ChannelGeometry.xFraction(WifiBand.ghz24, 2490), 1);
      expect(ChannelGeometry.yFraction(-100), 0);
      expect(ChannelGeometry.yFraction(-30), 1);
      expect(ChannelGeometry.yFraction(-65), closeTo(0.5, 1e-9));
      expect(ChannelGeometry.yFraction(-120), 0); // clamped
    });

    test('bell is smooth, symmetric and peaks in the middle', () {
      expect(ChannelGeometry.bell(0), 1);
      expect(
        ChannelGeometry.bell(0.4),
        closeTo(ChannelGeometry.bell(-0.4), 1e-12),
      );
      expect(ChannelGeometry.bell(1), 0);
      expect(ChannelGeometry.bell(0.2), greaterThan(ChannelGeometry.bell(0.6)));
      expect(ChannelGeometry.bell(0.98), lessThan(0.01));
    });

    test('inBand filters, drops unknown RSSI and sorts strongest first', () {
      final list = ChannelGeometry.inBand(const [
        WifiScanInfo(bssid: 'a', rssi: -70, frequencyMhz: 2412),
        WifiScanInfo(bssid: 'b', rssi: -40, frequencyMhz: 2437),
        WifiScanInfo(bssid: 'c', rssi: -50, frequencyMhz: 5180),
        WifiScanInfo(bssid: 'd', frequencyMhz: 2462),
      ], WifiBand.ghz24);
      expect(list.map((e) => e.bssid), ['b', 'a']);
    });
  });

  group('ChannelPainter.apAt', () {
    const size = Size(400, 228);
    const aps = [
      WifiScanInfo(
        bssid: 'strong',
        rssi: -40,
        frequencyMhz: 2437,
        channelWidthCode: 0,
      ),
      WifiScanInfo(
        bssid: 'weak',
        rssi: -85,
        frequencyMhz: 2462,
        channelWidthCode: 0,
      ),
    ];

    test('tap inside a curve selects it, tap outside selects nothing', () {
      final plot = ChannelPainter.plotRect(size);
      final x =
          plot.left +
          ChannelGeometry.xFraction(WifiBand.ghz24, 2437) * plot.width;
      expect(
        ChannelPainter.apAt(
          Offset(x, plot.bottom - 20),
          size,
          aps,
          WifiBand.ghz24,
        ),
        'strong',
      );
      // Far above the curve of the weak AP and outside the strong AP.
      final xWeak =
          plot.left +
          ChannelGeometry.xFraction(WifiBand.ghz24, 2462) * plot.width;
      expect(
        ChannelPainter.apAt(
          Offset(xWeak, plot.top + 5),
          size,
          aps,
          WifiBand.ghz24,
        ),
        isNull,
      );
      expect(
        ChannelPainter.apAt(
          Offset(plot.left + 1, 100),
          size,
          const [],
          WifiBand.ghz24,
        ),
        isNull,
      );
    });
  });

  group('ChannelGraph widget', () {
    Widget host(List<WifiScanInfo> aps) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ChannelGraph(
            aps: aps,
            band: WifiBand.ghz24,
            connectedBssid: 'aa:aa',
          ),
        ),
      ),
    );

    testWidgets('shows a legend and details of the tapped chip', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const [
          WifiScanInfo(
            bssid: 'aa:aa',
            ssid: 'Home',
            rssi: -48,
            frequencyMhz: 2437,
            channelWidthCode: 0,
          ),
          WifiScanInfo(
            bssid: 'bb:bb',
            ssid: 'Cafe',
            rssi: -77,
            frequencyMhz: 2462,
            channelWidthCode: 0,
          ),
        ]),
      );
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Cafe'), findsOneWidget);
      expect(find.text('BSSID'), findsNothing);

      await tester.tap(find.text('Cafe'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('BSSID'), findsOneWidget);
      expect(find.text('bb:bb'), findsOneWidget);
      expect(find.text('2412–2448 MHz'), findsNothing);
      expect(find.text('2451–2473 MHz'), findsOneWidget);

      await tester.tap(find.text('Cafe').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('BSSID'), findsNothing);
    });

    testWidgets('empty band shows a message instead of an empty chart', (
      tester,
    ) async {
      await tester.pumpWidget(host(const []));
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('No access points found on this band'), findsOneWidget);
    });
  });

  test('access point colour is stable and case-insensitive', () {
    expect(
      channelColorOf('AA:BB:CC:00:11:22'),
      channelColorOf('aa:bb:cc:00:11:22'),
    );
    expect(kChannelPalette, contains(channelColorOf('x')));
  });
}
