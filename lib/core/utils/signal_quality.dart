import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum SignalGrade {
  excellent('quality.excellent', SignalColors.excellent),
  good('quality.good', SignalColors.good),
  fair('quality.fair', SignalColors.fair),
  poor('quality.poor', SignalColors.poor),
  bad('quality.bad', SignalColors.bad),
  none('quality.none', SignalColors.none);

  const SignalGrade(this.labelKey, this.color);
  final String labelKey;
  final Color color;
}

/// Reference grading used only for colouring and labels; the numeric values
/// shown to the user are always the raw system-reported ones.
class SignalQuality {
  SignalQuality._();

  /// LTE RSRP / NR SS-RSRP in dBm.
  static SignalGrade rsrp(num? dbm) {
    if (dbm == null) return SignalGrade.none;
    if (dbm >= -80) return SignalGrade.excellent;
    if (dbm >= -90) return SignalGrade.good;
    if (dbm >= -100) return SignalGrade.fair;
    if (dbm >= -110) return SignalGrade.poor;
    return SignalGrade.bad;
  }

  /// GSM / WCDMA / TD-SCDMA RSSI-like dBm.
  static SignalGrade legacyDbm(num? dbm) {
    if (dbm == null) return SignalGrade.none;
    if (dbm >= -70) return SignalGrade.excellent;
    if (dbm >= -85) return SignalGrade.good;
    if (dbm >= -100) return SignalGrade.fair;
    if (dbm >= -110) return SignalGrade.poor;
    return SignalGrade.bad;
  }

  /// Wi-Fi RSSI in dBm.
  static SignalGrade wifiRssi(num? dbm) {
    if (dbm == null) return SignalGrade.none;
    if (dbm >= -50) return SignalGrade.excellent;
    if (dbm >= -60) return SignalGrade.good;
    if (dbm >= -70) return SignalGrade.fair;
    if (dbm >= -80) return SignalGrade.poor;
    return SignalGrade.bad;
  }

  /// C/N0 in dB-Hz.
  static SignalGrade cn0(num? v) {
    if (v == null || v <= 0) return SignalGrade.none;
    if (v >= 40) return SignalGrade.excellent;
    if (v >= 32) return SignalGrade.good;
    if (v >= 25) return SignalGrade.fair;
    if (v >= 18) return SignalGrade.poor;
    return SignalGrade.bad;
  }

  /// Gauge fill 0..1 for a value in `[min, max]`.
  static double fraction(num? v, {required double min, required double max}) {
    if (v == null) return 0;
    return ((v - min) / (max - min)).clamp(0.0, 1.0).toDouble();
  }
}
