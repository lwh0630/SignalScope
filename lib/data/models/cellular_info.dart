import '../../core/utils/network_type.dart';
import 'cell_signal_info.dart';
import 'model_utils.dart';

/// One real-time cellular snapshot for a single subscription.
class CellularInfo {
  const CellularInfo({
    required this.subscriptionId,
    required this.timestampMs,
    this.signalLevel,
    this.serviceState,
    this.operatorName,
    this.networkOperator,
    this.isRoaming,
    this.dataNetworkType,
    this.voiceNetworkType,
    this.hasDataNetwork,
    this.ipv4,
    this.ipv6 = const [],
    this.ipv6LinkLocal = const [],
    this.overrideNetworkType,
    this.primaryRat,
    this.primaryDbm,
    this.lte = const [],
    this.nr = const [],
    this.legacy = const [],
    this.cellInfoAvailable = false,
    this.issues = const [],
  });

  final int subscriptionId;

  /// Wall-clock time (ms since epoch) when native code produced this snapshot.
  final int timestampMs;

  /// Whether this SIM currently owns a mobile-data network. `null` = unknown
  /// (older native snapshot). Only the default-data SIM normally has one.
  final bool? hasDataNetwork;

  /// IPv4 address of this SIM's data network; `null` if it has none.
  final String? ipv4;

  /// Global IPv6 addresses of this SIM's data network.
  final List<String> ipv6;

  /// Link-local (`fe80::`) addresses, not routable.
  final List<String> ipv6LinkLocal;

  /// `SignalStrength.getLevel()` 0..4, as reported by the system.
  final int? signalLevel;

  /// `ServiceState.getState()`: 0 in service, 1 out of service, 2 emergency
  /// only, 3 power off.
  final int? serviceState;
  final String? operatorName;

  /// Registered network PLMN (MCC+MNC).
  final String? networkOperator;
  final bool? isRoaming;
  final int? dataNetworkType;
  final int? voiceNetworkType;

  /// `TelephonyDisplayInfo.getOverrideNetworkType()` (API 30+).
  final int? overrideNetworkType;

  /// RAT and dBm of the first entry in `SignalStrength.getCellSignalStrengths()`.
  final String? primaryRat;
  final int? primaryDbm;

  final List<LteSignalInfo> lte;
  final List<NrSignalInfo> nr;
  final List<LegacyCellInfo> legacy;

  /// Whether a CellInfo list (with cell identities) was returned by the OS.
  final bool cellInfoAvailable;

  /// Reason codes explaining missing data, e.g. `no_location_permission`,
  /// `no_phone_permission`, `cell_info_empty`.
  final List<String> issues;

  NetworkGeneration get generation => NetworkTypes.generation(dataNetworkType);

  /// Derived from public data only; `null` when it cannot be decided.
  String? get nrMode => NetworkTypes.nrMode(
    dataNetworkType: dataNetworkType,
    overrideNetworkType: overrideNetworkType,
  );

  LteSignalInfo? get servingLte {
    for (final c in lte) {
      if (c.isRegistered == true && c.source == CellDataSource.cellInfo) {
        return c;
      }
    }
    for (final c in lte) {
      if (c.source == CellDataSource.signalStrength) return c;
    }
    return null;
  }

  NrSignalInfo? get servingNr {
    for (final c in nr) {
      if (c.isRegistered == true && c.source == CellDataSource.cellInfo) {
        return c;
      }
    }
    for (final c in nr) {
      if (c.source == CellDataSource.signalStrength) return c;
    }
    return null;
  }

  LegacyCellInfo? get servingLegacy {
    for (final c in legacy) {
      if (c.isRegistered == true) return c;
    }
    for (final c in legacy) {
      if (c.source == CellDataSource.signalStrength) return c;
    }
    return null;
  }

  List<LteSignalInfo> get neighborLte => lte
      .where(
        (c) => c.source == CellDataSource.cellInfo && c.isRegistered != true,
      )
      .toList(growable: false);

  List<NrSignalInfo> get neighborNr => nr
      .where(
        (c) => c.source == CellDataSource.cellInfo && c.isRegistered != true,
      )
      .toList(growable: false);

  List<LegacyCellInfo> get neighborLegacy => legacy
      .where(
        (c) => c.source == CellDataSource.cellInfo && c.isRegistered != true,
      )
      .toList(growable: false);

  /// The signal quantity (dBm) and RAT label used by the main gauge.
  ///
  /// Chosen from the data network type so that LTE values are never shown as
  /// NR. In NSA the LTE anchor is the primary cell and NR is reported
  /// separately.
  ({String rat, String metric, int dbm})? get gaugeReading {
    final type = dataNetworkType;
    if (type == NetworkTypes.nr) {
      final nr = servingNr;
      if (nr?.ssRsrp != null) {
        return (rat: 'NR', metric: 'SS-RSRP', dbm: nr!.ssRsrp!);
      }
      if (nr?.csiRsrp != null) {
        return (rat: 'NR', metric: 'CSI-RSRP', dbm: nr!.csiRsrp!);
      }
    }
    if (type == NetworkTypes.lte || type == NetworkTypes.lteCa) {
      final v = servingLte?.rsrp;
      if (v != null) return (rat: 'LTE', metric: 'RSRP', dbm: v);
    }
    final legacyDbm = servingLegacy?.dbm;
    final gen = generation;
    if (legacyDbm != null &&
        (gen == NetworkGeneration.g2 || gen == NetworkGeneration.g3)) {
      return (rat: servingLegacy!.rat, metric: 'RSSI', dbm: legacyDbm);
    }
    if (primaryRat != null && primaryDbm != null) {
      final isLteNr = primaryRat == 'LTE' || primaryRat == 'NR';
      return (
        rat: primaryRat!,
        metric: isLteNr ? 'RSRP' : 'RSSI',
        dbm: primaryDbm!,
      );
    }
    return null;
  }

  CellularInfo withCells({
    required List<LteSignalInfo> lte,
    required List<NrSignalInfo> nr,
  }) => CellularInfo(
    subscriptionId: subscriptionId,
    timestampMs: timestampMs,
    signalLevel: signalLevel,
    serviceState: serviceState,
    operatorName: operatorName,
    networkOperator: networkOperator,
    isRoaming: isRoaming,
    dataNetworkType: dataNetworkType,
    voiceNetworkType: voiceNetworkType,
    hasDataNetwork: hasDataNetwork,
    ipv4: ipv4,
    ipv6: ipv6,
    ipv6LinkLocal: ipv6LinkLocal,
    overrideNetworkType: overrideNetworkType,
    primaryRat: primaryRat,
    primaryDbm: primaryDbm,
    lte: lte,
    nr: nr,
    legacy: legacy,
    cellInfoAvailable: cellInfoAvailable,
    issues: issues,
  );

  factory CellularInfo.fromMap(Map<Object?, Object?> m) => CellularInfo(
    subscriptionId: asInt(m['subscriptionId']) ?? -1,
    timestampMs:
        asInt(m['timestampMs']) ?? DateTime.now().millisecondsSinceEpoch,
    signalLevel: asInt(m['signalLevel']),
    serviceState: asInt(m['serviceState']),
    operatorName: asString(m['operatorName']),
    networkOperator: asString(m['networkOperator']),
    isRoaming: asBool(m['isRoaming']),
    dataNetworkType: asInt(m['dataNetworkType']),
    voiceNetworkType: asInt(m['voiceNetworkType']),
    hasDataNetwork: asBool(m['hasDataNetwork']),
    ipv4: asString(m['ipv4']),
    ipv6: asStringList(m['ipv6']),
    ipv6LinkLocal: asStringList(m['ipv6LinkLocal']),
    overrideNetworkType: asInt(m['overrideNetworkType']),
    primaryRat: asString(m['primaryRat']),
    primaryDbm: asInt(m['primaryDbm']),
    lte: asMapList(m['lte']).map(LteSignalInfo.fromMap).toList(growable: false),
    nr: asMapList(m['nr']).map(NrSignalInfo.fromMap).toList(growable: false),
    legacy: asMapList(m['legacy'])
        .map(LegacyCellInfo.fromMap)
        .toList(growable: false),
    cellInfoAvailable: asBool(m['cellInfoAvailable']) ?? false,
    issues: asStringList(m['issues']),
  );

  Map<String, Object?> toMap() => {
    'subscriptionId': subscriptionId,
    'timestampMs': timestampMs,
    'signalLevel': signalLevel,
    'serviceState': serviceState,
    'operatorName': operatorName,
    'networkOperator': networkOperator,
    'isRoaming': isRoaming,
    'dataNetworkType': dataNetworkType,
    'dataNetworkTypeName': NetworkTypes.name(dataNetworkType),
    'voiceNetworkType': voiceNetworkType,
    'hasDataNetwork': hasDataNetwork,
    'ipv4': ipv4,
    'ipv6': ipv6,
    'ipv6LinkLocal': ipv6LinkLocal,
    'overrideNetworkType': overrideNetworkType,
    'nrMode_derived': nrMode,
    'primaryRat': primaryRat,
    'primaryDbm': primaryDbm,
    'lte': lte.map((e) => e.toMap()).toList(),
    'nr': nr.map((e) => e.toMap()).toList(),
    'legacy': legacy.map((e) => e.toMap()).toList(),
    'cellInfoAvailable': cellInfoAvailable,
    'issues': issues,
  };
}
