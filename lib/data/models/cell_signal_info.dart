import 'model_utils.dart';

/// Where a cell entry was obtained from.
///
/// * [cellInfo]: from `TelephonyManager.requestCellInfoUpdate` / `CellInfo`
///   (contains cell identity such as PCI / TAC / CI).
/// * [signalStrength]: from `SignalStrength.getCellSignalStrengths()`
///   (measurements only, no cell identity). On 5G NSA devices this is often
///   the only place NR measurements are exposed.
enum CellDataSource {
  cellInfo,
  signalStrength;

  static CellDataSource parse(Object? v) => v == 'signalStrength'
      ? CellDataSource.signalStrength
      : CellDataSource.cellInfo;
}

/// Origin of a band number shown in the UI.
enum BandSource {
  /// Reported by Android (`CellIdentityLte.getBands()` / `CellIdentityNr.getBands()`).
  reported,

  /// Derived from EARFCN / NRARFCN with a 3GPP table, only when unambiguous.
  derived,
}

/// LTE serving or neighbour cell. Units are preserved as reported by Android.
class LteSignalInfo {
  const LteSignalInfo({
    this.isRegistered,
    this.source = CellDataSource.cellInfo,
    this.rsrp,
    this.rsrq,
    this.rssi,
    this.rssnr,
    this.cqi,
    this.timingAdvance,
    this.level,
    this.dbm,
    this.pci,
    this.tac,
    this.ci,
    this.earfcn,
    this.bandwidthKhz,
    this.bands = const [],
    this.bandSource,
    this.mcc,
    this.mnc,
  });

  final bool? isRegistered;
  final CellDataSource source;

  /// dBm
  final int? rsrp;

  /// dB
  final int? rsrq;

  /// dBm
  final int? rssi;

  /// dB (RSSNR, commonly referred to as SINR)
  final int? rssnr;
  final int? cqi;
  final int? timingAdvance;
  final int? level;
  final int? dbm;
  final int? pci;
  final int? tac;

  /// 28-bit E-UTRAN Cell Identity (ECI).
  final int? ci;
  final int? earfcn;
  final int? bandwidthKhz;
  final List<int> bands;
  final BandSource? bandSource;
  final String? mcc;
  final String? mnc;

  /// Derived value: eNodeB ID = ECI >> 8.
  int? get enbId => ci == null ? null : ci! >> 8;

  /// Derived value: cell ID within the eNodeB = ECI & 0xFF.
  int? get localCellId => ci == null ? null : ci! & 0xFF;

  bool get hasMeasurements =>
      rsrp != null || rsrq != null || rssi != null || rssnr != null;

  factory LteSignalInfo.fromMap(Map<Object?, Object?> m) => LteSignalInfo(
    isRegistered: asBool(m['isRegistered']),
    source: CellDataSource.parse(m['source']),
    rsrp: asInt(m['rsrp']),
    rsrq: asInt(m['rsrq']),
    rssi: asInt(m['rssi']),
    rssnr: asInt(m['rssnr']),
    cqi: asInt(m['cqi']),
    timingAdvance: asInt(m['timingAdvance']),
    level: asInt(m['level']),
    dbm: asInt(m['dbm']),
    pci: asInt(m['pci']),
    tac: asInt(m['tac']),
    ci: asInt(m['ci']),
    earfcn: asInt(m['earfcn']),
    bandwidthKhz: asInt(m['bandwidthKhz']),
    bands: asIntList(m['bands']),
    bandSource: asIntList(m['bands']).isEmpty ? null : BandSource.reported,
    mcc: asString(m['mcc']),
    mnc: asString(m['mnc']),
  );

  LteSignalInfo withBands(List<int> newBands, BandSource? newSource) =>
      LteSignalInfo(
        isRegistered: isRegistered,
        source: source,
        rsrp: rsrp,
        rsrq: rsrq,
        rssi: rssi,
        rssnr: rssnr,
        cqi: cqi,
        timingAdvance: timingAdvance,
        level: level,
        dbm: dbm,
        pci: pci,
        tac: tac,
        ci: ci,
        earfcn: earfcn,
        bandwidthKhz: bandwidthKhz,
        bands: newBands,
        bandSource: newSource,
        mcc: mcc,
        mnc: mnc,
      );

  Map<String, Object?> toMap() => {
    'isRegistered': isRegistered,
    'source': source.name,
    'rsrp_dBm': rsrp,
    'rsrq_dB': rsrq,
    'rssi_dBm': rssi,
    'rssnr_dB': rssnr,
    'cqi': cqi,
    'timingAdvance': timingAdvance,
    'level': level,
    'dbm': dbm,
    'pci': pci,
    'tac': tac,
    'eci': ci,
    'enbId_derived': enbId,
    'earfcn': earfcn,
    'bandwidth_kHz': bandwidthKhz,
    'bands': bands,
    'bandSource': bandSource?.name,
    'mcc': mcc,
    'mnc': mnc,
  };
}

/// 5G NR serving or neighbour cell.
class NrSignalInfo {
  const NrSignalInfo({
    this.isRegistered,
    this.source = CellDataSource.cellInfo,
    this.ssRsrp,
    this.ssRsrq,
    this.ssSinr,
    this.csiRsrp,
    this.csiRsrq,
    this.csiSinr,
    this.level,
    this.dbm,
    this.nrarfcn,
    this.pci,
    this.tac,
    this.nci,
    this.bands = const [],
    this.bandSource,
    this.mcc,
    this.mnc,
  });

  final bool? isRegistered;
  final CellDataSource source;

  /// dBm
  final int? ssRsrp;

  /// dB
  final int? ssRsrq;

  /// dB
  final int? ssSinr;

  /// dBm
  final int? csiRsrp;

  /// dB
  final int? csiRsrq;

  /// dB
  final int? csiSinr;
  final int? level;
  final int? dbm;
  final int? nrarfcn;
  final int? pci;
  final int? tac;

  /// 36-bit NR Cell Identity.
  final int? nci;
  final List<int> bands;
  final BandSource? bandSource;
  final String? mcc;
  final String? mnc;

  bool get hasMeasurements =>
      ssRsrp != null ||
      ssRsrq != null ||
      ssSinr != null ||
      csiRsrp != null ||
      csiRsrq != null ||
      csiSinr != null;

  factory NrSignalInfo.fromMap(Map<Object?, Object?> m) => NrSignalInfo(
    isRegistered: asBool(m['isRegistered']),
    source: CellDataSource.parse(m['source']),
    ssRsrp: asInt(m['ssRsrp']),
    ssRsrq: asInt(m['ssRsrq']),
    ssSinr: asInt(m['ssSinr']),
    csiRsrp: asInt(m['csiRsrp']),
    csiRsrq: asInt(m['csiRsrq']),
    csiSinr: asInt(m['csiSinr']),
    level: asInt(m['level']),
    dbm: asInt(m['dbm']),
    nrarfcn: asInt(m['nrarfcn']),
    pci: asInt(m['pci']),
    tac: asInt(m['tac']),
    nci: asInt(m['nci']),
    bands: asIntList(m['bands']),
    bandSource: asIntList(m['bands']).isEmpty ? null : BandSource.reported,
    mcc: asString(m['mcc']),
    mnc: asString(m['mnc']),
  );

  NrSignalInfo withBands(List<int> newBands, BandSource? newSource) =>
      NrSignalInfo(
        isRegistered: isRegistered,
        source: source,
        ssRsrp: ssRsrp,
        ssRsrq: ssRsrq,
        ssSinr: ssSinr,
        csiRsrp: csiRsrp,
        csiRsrq: csiRsrq,
        csiSinr: csiSinr,
        level: level,
        dbm: dbm,
        nrarfcn: nrarfcn,
        pci: pci,
        tac: tac,
        nci: nci,
        bands: newBands,
        bandSource: newSource,
        mcc: mcc,
        mnc: mnc,
      );

  Map<String, Object?> toMap() => {
    'isRegistered': isRegistered,
    'source': source.name,
    'ssRsrp_dBm': ssRsrp,
    'ssRsrq_dB': ssRsrq,
    'ssSinr_dB': ssSinr,
    'csiRsrp_dBm': csiRsrp,
    'csiRsrq_dB': csiRsrq,
    'csiSinr_dB': csiSinr,
    'level': level,
    'dbm': dbm,
    'nrarfcn': nrarfcn,
    'pci': pci,
    'tac': tac,
    'nci': nci,
    'bands': bands,
    'bandSource': bandSource?.name,
    'mcc': mcc,
    'mnc': mnc,
  };
}

/// 2G / 3G cell (GSM, WCDMA, TD-SCDMA) or CDMA cell.
class LegacyCellInfo {
  const LegacyCellInfo({
    required this.rat,
    this.isRegistered,
    this.source = CellDataSource.cellInfo,
    this.dbm,
    this.level,
    this.cid,
    this.lac,
    this.channel,
    this.psc,
    this.bsic,
    this.mcc,
    this.mnc,
  });

  /// `GSM`, `WCDMA`, `TDSCDMA`, `CDMA`.
  final String rat;
  final bool? isRegistered;
  final CellDataSource source;
  final int? dbm;
  final int? level;
  final int? cid;
  final int? lac;

  /// ARFCN (GSM) or UARFCN (WCDMA / TD-SCDMA).
  final int? channel;

  /// Primary scrambling code (WCDMA).
  final int? psc;

  /// Base station identity code (GSM).
  final int? bsic;
  final String? mcc;
  final String? mnc;

  factory LegacyCellInfo.fromMap(Map<Object?, Object?> m) => LegacyCellInfo(
    rat: asString(m['rat']) ?? 'UNKNOWN',
    isRegistered: asBool(m['isRegistered']),
    source: CellDataSource.parse(m['source']),
    dbm: asInt(m['dbm']),
    level: asInt(m['level']),
    cid: asInt(m['cid']),
    lac: asInt(m['lac']),
    channel: asInt(m['channel']),
    psc: asInt(m['psc']),
    bsic: asInt(m['bsic']),
    mcc: asString(m['mcc']),
    mnc: asString(m['mnc']),
  );

  Map<String, Object?> toMap() => {
    'rat': rat,
    'isRegistered': isRegistered,
    'source': source.name,
    'dbm': dbm,
    'level': level,
    'cid': cid,
    'lac': lac,
    'channel': channel,
    'psc': psc,
    'bsic': bsic,
    'mcc': mcc,
    'mnc': mnc,
  };
}
