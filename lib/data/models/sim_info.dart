import 'model_utils.dart';

/// Information about one active SIM subscription.
///
/// Every value comes from Android public APIs (SubscriptionManager /
/// TelephonyManager). `null` means the system did not report the value
/// (missing permission, no SIM, unsupported by the device or OS version).
class SimInfo {
  const SimInfo({
    required this.subscriptionId,
    this.slotIndex,
    this.displayName,
    this.carrierName,
    this.mcc,
    this.mnc,
    this.countryIso,
    this.simState,
    this.simOperator,
    this.simOperatorName,
    this.networkOperator,
    this.networkOperatorName,
    this.networkCountryIso,
    this.isRoaming,
    this.isEmbedded,
    this.isDefaultData = false,
    this.isDataEnabled,
    this.dataState,
    this.dataNetworkType,
    this.voiceNetworkType,
  });

  final int subscriptionId;

  /// 0-based physical slot index. UI shows `slotIndex + 1` as SIM1/SIM2.
  final int? slotIndex;
  final String? displayName;
  final String? carrierName;

  /// MCC / MNC of the SIM subscription (home network).
  final String? mcc;
  final String? mnc;
  final String? countryIso;

  /// `TelephonyManager.SIM_STATE_*`.
  final int? simState;

  /// MCC+MNC of the SIM provider.
  final String? simOperator;
  final String? simOperatorName;

  /// MCC+MNC of the currently registered network (differs when roaming).
  final String? networkOperator;
  final String? networkOperatorName;
  final String? networkCountryIso;
  final bool? isRoaming;

  /// True for eSIM, false for a removable SIM, null when the OS does not say.
  final bool? isEmbedded;
  final bool isDefaultData;
  final bool? isDataEnabled;

  /// `TelephonyManager.DATA_*`.
  final int? dataState;

  /// `TelephonyManager.NETWORK_TYPE_*`.
  final int? dataNetworkType;
  final int? voiceNetworkType;

  String get slotLabel => slotIndex == null ? 'SIM' : 'SIM${slotIndex! + 1}';

  factory SimInfo.fromMap(Map<Object?, Object?> m) => SimInfo(
    subscriptionId: asInt(m['subscriptionId']) ?? -1,
    slotIndex: asInt(m['slotIndex']),
    displayName: asString(m['displayName']),
    carrierName: asString(m['carrierName']),
    mcc: asString(m['mcc']),
    mnc: asString(m['mnc']),
    countryIso: asString(m['countryIso']),
    simState: asInt(m['simState']),
    simOperator: asString(m['simOperator']),
    simOperatorName: asString(m['simOperatorName']),
    networkOperator: asString(m['networkOperator']),
    networkOperatorName: asString(m['networkOperatorName']),
    networkCountryIso: asString(m['networkCountryIso']),
    isRoaming: asBool(m['isRoaming']),
    isEmbedded: asBool(m['isEmbedded']),
    isDefaultData: asBool(m['isDefaultData']) ?? false,
    isDataEnabled: asBool(m['isDataEnabled']),
    dataState: asInt(m['dataState']),
    dataNetworkType: asInt(m['dataNetworkType']),
    voiceNetworkType: asInt(m['voiceNetworkType']),
  );

  Map<String, Object?> toMap() => {
    'subscriptionId': subscriptionId,
    'slotIndex': slotIndex,
    'displayName': displayName,
    'carrierName': carrierName,
    'mcc': mcc,
    'mnc': mnc,
    'countryIso': countryIso,
    'simState': simState,
    'simOperator': simOperator,
    'simOperatorName': simOperatorName,
    'networkOperator': networkOperator,
    'networkOperatorName': networkOperatorName,
    'networkCountryIso': networkCountryIso,
    'isRoaming': isRoaming,
    'isEmbedded': isEmbedded,
    'isDefaultData': isDefaultData,
    'isDataEnabled': isDataEnabled,
    'dataState': dataState,
    'dataNetworkType': dataNetworkType,
    'voiceNetworkType': voiceNetworkType,
  };
}
