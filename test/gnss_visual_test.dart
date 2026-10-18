import 'package:flutter/material.dart';
import 'package:flutter_application/data/models/gnss_info.dart';
import 'package:flutter_application/features/gnss/presentation/cn0_bars.dart';
import 'package:flutter_application/features/gnss/presentation/constellation_flag.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConstellationFlag', () {
    test('builds flag emoji from ISO codes', () {
      expect(ConstellationFlag.fromIso('US'), '\u{1F1FA}\u{1F1F8}');
      expect(ConstellationFlag.fromIso('cn'), '\u{1F1E8}\u{1F1F3}');
    });

    test('every constellation maps to its operator', () {
      expect(ConstellationFlag.of(Constellation.gps).emoji, '🇺🇸');
      expect(ConstellationFlag.of(Constellation.glonass).emoji, '🇷🇺');
      expect(ConstellationFlag.of(Constellation.beidou).emoji, '🇨🇳');
      expect(ConstellationFlag.of(Constellation.galileo).emoji, '🇪🇺');
      expect(ConstellationFlag.of(Constellation.qzss).emoji, '🇯🇵');
      expect(ConstellationFlag.of(Constellation.irnss).emoji, '🇮🇳');
      // SBAS is a family of regional systems: no single national flag.
      expect(ConstellationFlag.of(Constellation.sbas).emoji, '🌐');
      for (final c in Constellation.values) {
        expect(ConstellationFlag.of(c).countryKey, startsWith('gnss.country.'));
      }
    });
  });

  group('C/N0 chart model', () {
    const sats = [
      SatelliteInfo(svid: 9, constellation: Constellation.beidou, cn0DbHz: 30),
      SatelliteInfo(svid: 20, constellation: Constellation.gps, cn0DbHz: 40),
      SatelliteInfo(svid: 3, constellation: Constellation.gps, cn0DbHz: 0),
      SatelliteInfo(svid: 2, constellation: Constellation.galileo),
    ];

    test('groups by constellation in a stable order', () {
      final g = groupByConstellation(sats);
      expect(g.map((e) => e.map((s) => s.svid).toList()), [
        [3, 20],
        [9],
        [2],
      ]);
      expect(groupByConstellation(const []), isEmpty);
    });

    test('layout positions bars left to right and leaves gaps between groups', () {
      final layout = Cn0Layout(groupByConstellation(sats));
      final lefts = layout.slots.map((s) => s.left).toList();
      expect(lefts, orderedEquals([...lefts]..sort()));
      final within = lefts[1] - lefts[0];
      final across = lefts[2] - lefts[1];
      expect(within, Cn0Layout.slot);
      expect(across, Cn0Layout.slot + Cn0Layout.groupGap);
      expect(layout.spans.length, 3);
      expect(layout.contentWidth, greaterThan(lefts.last + Cn0Layout.barW));
    });

    test('tap position resolves to a bar, gaps far from bars resolve to none', () {
      final layout = Cn0Layout(groupByConstellation(sats));
      final first = layout.slots.first;
      expect(layout.slotAt(first.left + Cn0Layout.barW / 2), 0);
      expect(layout.slotAt(layout.slots.last.left + 300), -1);
    });

    test('bar height maps 0..60 dB-Hz onto the plot', () {
      expect(Cn0Layout.yOf(0), Cn0Layout.plotBottom);
      expect(Cn0Layout.yOf(60), Cn0Layout.plotTop);
      expect(Cn0Layout.yOf(30), closeTo((Cn0Layout.plotTop + Cn0Layout.plotBottom) / 2, 1e-9));
      expect(Cn0Layout.yOf(99), Cn0Layout.plotTop); // clamped
    });
  });

  testWidgets('tapping a bar shows that satellite, tapping again hides it', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Cn0Bars(satellites: [
            SatelliteInfo(
              svid: 7,
              constellation: Constellation.beidou,
              azimuthDeg: 120,
              elevationDeg: 45,
              cn0DbHz: 38.5,
              usedInFix: true,
            ),
            SatelliteInfo(svid: 12, constellation: Constellation.gps, cn0DbHz: 0, usedInFix: false),
          ]),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Tap a bar to see that satellite'), findsOneWidget);

    // GPS group comes first (code 1), BeiDou second; tap the BeiDou bar.
    final layout = Cn0Layout(groupByConstellation(const [
      SatelliteInfo(svid: 7, constellation: Constellation.beidou),
      SatelliteInfo(svid: 12, constellation: Constellation.gps),
    ]));
    final beidou = layout.slots[1];
    final origin = tester.getTopLeft(find.byType(Cn0Bars));
    await tester.tapAt(origin + Offset(30 + beidou.left + Cn0Layout.barW / 2, Cn0Layout.plotTop + 60));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('BeiDou 7'), findsOneWidget);
    expect(find.text('38.5 dB-Hz'), findsOneWidget);

    await tester.tapAt(origin + Offset(30 + beidou.left + Cn0Layout.barW / 2, Cn0Layout.plotTop + 60));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('BeiDou 7'), findsNothing);
  });
}
