/// Mapping of `TelephonyManager.NETWORK_TYPE_*` constants.
library;

enum NetworkGeneration { none, g2, g3, g4, g5 }

class NetworkTypes {
  NetworkTypes._();

  static const int unknown = 0;
  static const int lte = 13;
  static const int lteCa = 19; // value reported by many devices for LTE-CA
  static const int nr = 20;

  static const Map<int, String> _names = {
    0: 'UNKNOWN',
    1: 'GPRS',
    2: 'EDGE',
    3: 'UMTS',
    4: 'CDMA',
    5: 'EVDO_0',
    6: 'EVDO_A',
    7: '1xRTT',
    8: 'HSDPA',
    9: 'HSUPA',
    10: 'HSPA',
    11: 'iDEN',
    12: 'EVDO_B',
    13: 'LTE',
    14: 'eHRPD',
    15: 'HSPA+',
    16: 'GSM',
    17: 'TD-SCDMA',
    18: 'IWLAN',
    19: 'LTE-CA',
    20: 'NR',
  };

  /// Display name; null when the type is unknown or absent.
  static String? name(int? type) {
    if (type == null || type == unknown) return null;
    return _names[type] ?? 'TYPE_$type';
  }

  static NetworkGeneration generation(int? type) {
    switch (type) {
      case 1:
      case 2:
      case 4:
      case 7:
      case 11:
      case 16:
        return NetworkGeneration.g2;
      case 3:
      case 5:
      case 6:
      case 8:
      case 9:
      case 10:
      case 12:
      case 14:
      case 15:
      case 17:
        return NetworkGeneration.g3;
      case 13:
      case 19:
        return NetworkGeneration.g4;
      case 20:
        return NetworkGeneration.g5;
      default:
        return NetworkGeneration.none;
    }
  }

  static String generationLabel(NetworkGeneration g) {
    switch (g) {
      case NetworkGeneration.g2:
        return '2G';
      case NetworkGeneration.g3:
        return '3G';
      case NetworkGeneration.g4:
        return '4G';
      case NetworkGeneration.g5:
        return '5G';
      case NetworkGeneration.none:
        return '--';
    }
  }

  /// Public-API based NSA/SA decision.
  ///
  /// * `dataNetworkType == NR`  -> the device is camped on a 5G core: SA.
  /// * LTE data network + `TelephonyDisplayInfo.overrideNetworkType` is
  ///   `NR_NSA` (3), `NR_NSA_MMWAVE` (4) or `NR_ADVANCED` (5) -> NSA.
  ///
  /// Returns `null` when the public data is not sufficient to decide.
  static String? nrMode({int? dataNetworkType, int? overrideNetworkType}) {
    if (dataNetworkType == nr) return 'SA';
    final isLte = dataNetworkType == lte || dataNetworkType == lteCa;
    if (isLte &&
        (overrideNetworkType == 3 ||
            overrideNetworkType == 4 ||
            overrideNetworkType == 5)) {
      return 'NSA';
    }
    return null;
  }
}
