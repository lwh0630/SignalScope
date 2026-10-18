import 'model_utils.dart';

/// GNSS constellation types (`GnssStatus.CONSTELLATION_*`).
enum Constellation {
  unknown(0, 'Unknown'),
  gps(1, 'GPS'),
  sbas(2, 'SBAS'),
  glonass(3, 'GLONASS'),
  qzss(4, 'QZSS'),
  beidou(5, 'BeiDou'),
  galileo(6, 'Galileo'),
  irnss(7, 'IRNSS/NavIC');

  const Constellation(this.code, this.label);
  final int code;
  final String label;

  static Constellation fromCode(int? code) {
    for (final c in Constellation.values) {
      if (c.code == code) return c;
    }
    return Constellation.unknown;
  }
}

class SatelliteInfo {
  const SatelliteInfo({
    required this.svid,
    required this.constellation,
    this.azimuthDeg,
    this.elevationDeg,
    this.cn0DbHz,
    this.usedInFix,
    this.carrierFrequencyHz,
    this.basebandCn0DbHz,
  });

  final int svid;
  final Constellation constellation;

  /// Degrees clockwise from true north, 0..360.
  final double? azimuthDeg;

  /// Degrees above the horizon, -90..90.
  final double? elevationDeg;

  /// dB-Hz. `null` or 0 means the satellite is not being tracked.
  final double? cn0DbHz;
  final bool? usedInFix;
  final double? carrierFrequencyHz;
  final double? basebandCn0DbHz;

  /// Stable key for list diffing.
  String get key => '${constellation.code}-$svid';

  factory SatelliteInfo.fromMap(Map<Object?, Object?> m) => SatelliteInfo(
        svid: asInt(m['svid']) ?? -1,
        constellation: Constellation.fromCode(asInt(m['constellation'])),
        azimuthDeg: asDouble(m['azimuthDeg']),
        elevationDeg: asDouble(m['elevationDeg']),
        cn0DbHz: asDouble(m['cn0DbHz']),
        usedInFix: asBool(m['usedInFix']),
        carrierFrequencyHz: asDouble(m['carrierFrequencyHz']),
        basebandCn0DbHz: asDouble(m['basebandCn0DbHz']),
      );

  Map<String, Object?> toMap() => {
        'svid': svid,
        'constellation': constellation.label,
        'azimuth_deg': azimuthDeg,
        'elevation_deg': elevationDeg,
        'cn0_dBHz': cn0DbHz,
        'usedInFix': usedInFix,
        'carrierFrequency_Hz': carrierFrequencyHz,
        'basebandCn0_dBHz': basebandCn0DbHz,
      };
}

class GnssLocationInfo {
  const GnssLocationInfo({
    this.latitude,
    this.longitude,
    this.altitudeM,
    this.horizontalAccuracyM,
    this.verticalAccuracyM,
    this.speedMps,
    this.bearingDeg,
    this.timeMs,
    this.provider,
    this.isMock,
  });

  final double? latitude;
  final double? longitude;

  /// Metres above the WGS84 ellipsoid (`Location.getAltitude`).
  final double? altitudeM;
  final double? horizontalAccuracyM;
  final double? verticalAccuracyM;
  final double? speedMps;
  final double? bearingDeg;

  /// UTC fix time in ms since epoch.
  final int? timeMs;
  final String? provider;
  final bool? isMock;

  bool get hasFix => latitude != null && longitude != null;

  factory GnssLocationInfo.fromMap(Map<Object?, Object?> m) => GnssLocationInfo(
        latitude: asDouble(m['latitude']),
        longitude: asDouble(m['longitude']),
        altitudeM: asDouble(m['altitudeM']),
        horizontalAccuracyM: asDouble(m['horizontalAccuracyM']),
        verticalAccuracyM: asDouble(m['verticalAccuracyM']),
        speedMps: asDouble(m['speedMps']),
        bearingDeg: asDouble(m['bearingDeg']),
        timeMs: asInt(m['timeMs']),
        provider: asString(m['provider']),
        isMock: asBool(m['isMock']),
      );

  Map<String, Object?> toMap() => {
        'latitude_deg': latitude,
        'longitude_deg': longitude,
        'altitude_m': altitudeM,
        'horizontalAccuracy_m': horizontalAccuracyM,
        'verticalAccuracy_m': verticalAccuracyM,
        'speed_mps': speedMps,
        'bearing_deg': bearingDeg,
        'timeMs': timeMs,
        'provider': provider,
        'isMock': isMock,
      };
}

/// Combined GNSS state pushed by the native `GnssService`.
class GnssSnapshot {
  const GnssSnapshot({
    this.location,
    this.satellites = const [],
    this.ttffMs,
    this.gnssSupported,
    this.providerEnabled,
    this.engineStarted,
    this.issues = const [],
    this.timestampMs,
  });

  final GnssLocationInfo? location;
  final List<SatelliteInfo> satellites;

  /// Time-to-first-fix of the current session (ms), `null` until reported.
  final int? ttffMs;

  /// `null` when the capability could not be determined.
  final bool? gnssSupported;
  final bool? providerEnabled;
  final bool? engineStarted;
  final List<String> issues;
  final int? timestampMs;

  int get visibleCount => satellites.length;
  int get usedCount => satellites.where((s) => s.usedInFix == true).length;

  factory GnssSnapshot.fromMap(Map<Object?, Object?> m) {
    final loc = m['location'];
    return GnssSnapshot(
      location: loc is Map ? GnssLocationInfo.fromMap(loc.cast<Object?, Object?>()) : null,
      satellites: asMapList(m['satellites']).map(SatelliteInfo.fromMap).toList(growable: false),
      ttffMs: asInt(m['ttffMs']),
      gnssSupported: asBool(m['gnssSupported']),
      providerEnabled: asBool(m['providerEnabled']),
      engineStarted: asBool(m['engineStarted']),
      issues: asStringList(m['issues']),
      timestampMs: asInt(m['timestampMs']),
    );
  }

  Map<String, Object?> toMap() => {
        'timestampMs': timestampMs,
        'location': location?.toMap(),
        'visibleSatellites': visibleCount,
        'usedSatellites': usedCount,
        'ttff_ms': ttffMs,
        'satellites': satellites.map((e) => e.toMap()).toList(),
        'issues': issues,
      };
}
