import 'dart:math' as math;

import '../../../core/utils/wifi_utils.dart';
import '../../../data/models/wifi_info.dart';

/// Pure geometry of the channel graph, kept separate from painting so it can
/// be unit-tested. Everything is derived from what Android reported:
/// `ScanResult.frequency`, `centerFreq0` and `channelWidth`. When the OS gives
/// no width a 20 MHz channel is assumed.
class ChannelGeometry {
  ChannelGeometry._();

  static const double minRssi = -100;
  static const double maxRssi = -30;

  /// Visible frequency range of a band in MHz.
  static (double, double) range(WifiBand band) {
    switch (band) {
      case WifiBand.ghz24:
        return (2400, 2490);
      case WifiBand.ghz5:
        return (5150, 5895);
      case WifiBand.ghz6:
        return (5925, 7125);
      case WifiBand.unknown:
        return (0, 1);
    }
  }

  /// Channels that get a tick and a number on the X axis.
  static List<int> labelChannels(WifiBand band) {
    switch (band) {
      case WifiBand.ghz24:
        return const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13];
      case WifiBand.ghz5:
        return const [36, 52, 100, 116, 132, 149, 165];
      case WifiBand.ghz6:
        return const [1, 33, 65, 97, 129, 161, 193, 225];
      case WifiBand.unknown:
        return const [];
    }
  }

  /// Centre frequency (MHz) of an IEEE 802.11 channel number in [band].
  static double channelCenterMhz(WifiBand band, int channel) {
    switch (band) {
      case WifiBand.ghz24:
        return channel == 14 ? 2484 : 2407.0 + 5 * channel;
      case WifiBand.ghz5:
        return 5000.0 + 5 * channel;
      case WifiBand.ghz6:
        return 5950.0 + 5 * channel;
      case WifiBand.unknown:
        return 0;
    }
  }

  static double? centerMhz(WifiScanInfo ap) => (ap.centerFreq0Mhz ?? ap.frequencyMhz)?.toDouble();

  /// Occupied width in MHz. A 20 MHz 2.4 GHz transmission occupies ~22 MHz
  /// (DSSS mask), which is why neighbouring 2.4 GHz channels overlap.
  static double occupiedWidthMhz(WifiScanInfo ap) {
    final w = ap.channelWidthMhz ?? 20;
    if (ap.band == WifiBand.ghz24 && w == 20) return 22;
    return w.toDouble();
  }

  /// Lower / upper edge of the access point's spectrum in MHz.
  static (double, double)? span(WifiScanInfo ap) {
    final c = centerMhz(ap);
    if (c == null) return null;
    final half = occupiedWidthMhz(ap) / 2;
    return (c - half, c + half);
  }

  /// 0..1 position of [mhz] inside the band's visible range (not clamped).
  static double xFraction(WifiBand band, double mhz) {
    final (lo, hi) = range(band);
    return (mhz - lo) / (hi - lo);
  }

  /// 0..1 height of an RSSI value (-100 dBm = 0, -30 dBm = 1).
  static double yFraction(num rssi) =>
      ((rssi - minRssi) / (maxRssi - minRssi)).clamp(0.0, 1.0).toDouble();

  /// Smooth spectral-mask-like bell: flat-ish rounded top, steep sides that
  /// reach ~0 at the edges. [t] runs from -1 (lower edge) to 1 (upper edge).
  static double bell(double t) {
    final a = t.abs();
    if (a >= 1) return 0;
    final z = a / 0.56;
    return math.exp(-(z * z * z * z));
  }

  /// Access points of [band] that have an RSSI, strongest first.
  static List<WifiScanInfo> inBand(List<WifiScanInfo> all, WifiBand band) {
    return all.where((a) => a.band == band && a.rssi != null).toList()
      ..sort((a, b) => b.rssi!.compareTo(a.rssi!));
  }
}
