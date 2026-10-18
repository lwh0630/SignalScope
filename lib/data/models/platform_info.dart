import 'model_utils.dart';

enum PermStatus {
  granted,
  denied,
  permanentlyDenied,

  /// The permission does not exist on this Android version or platform.
  notApplicable;

  static PermStatus parse(Object? v) {
    switch (v) {
      case 'granted':
        return PermStatus.granted;
      case 'denied':
        return PermStatus.denied;
      case 'permanentlyDenied':
        return PermStatus.permanentlyDenied;
      default:
        return PermStatus.notApplicable;
    }
  }

  bool get isGranted => this == PermStatus.granted;
}

/// Runtime permission groups used by SignalScope.
enum PermGroup { location, phone, nearbyWifi }

class PermissionSnapshot {
  const PermissionSnapshot({
    this.location = PermStatus.notApplicable,
    this.phone = PermStatus.notApplicable,
    this.nearbyWifi = PermStatus.notApplicable,
    this.locationServicesEnabled,
    this.loaded = true,
  });

  const PermissionSnapshot.unsupported() : this();

  /// Placeholder used before the first native query returns.
  const PermissionSnapshot.loading() : this(loaded: false);

  /// False until the first native permission query has completed.
  final bool loaded;

  final PermStatus location;
  final PermStatus phone;
  final PermStatus nearbyWifi;

  /// System location switch. `null` when it cannot be determined.
  final bool? locationServicesEnabled;

  PermStatus of(PermGroup g) {
    switch (g) {
      case PermGroup.location:
        return location;
      case PermGroup.phone:
        return phone;
      case PermGroup.nearbyWifi:
        return nearbyWifi;
    }
  }

  factory PermissionSnapshot.fromMap(Map<Object?, Object?> m) =>
      PermissionSnapshot(
        location: PermStatus.parse(m['location']),
        phone: PermStatus.parse(m['phone']),
        nearbyWifi: PermStatus.parse(m['nearbyWifi']),
        locationServicesEnabled: asBool(m['locationServicesEnabled']),
      );
}

/// Device capabilities detected by native code.
class PlatformCapabilities {
  const PlatformCapabilities({
    this.platform = 'unknown',
    this.sdkInt,
    this.manufacturer,
    this.model,
    this.hasTelephony,
    this.hasWifi,
    this.hasGnss,
    this.wifiEnabled,
    this.simCount,
  });

  const PlatformCapabilities.unsupported(String platform)
    : this(platform: platform);

  final String platform;
  final int? sdkInt;
  final String? manufacturer;
  final String? model;
  final bool? hasTelephony;
  final bool? hasWifi;
  final bool? hasGnss;
  final bool? wifiEnabled;

  /// Number of active subscriptions (null if READ_PHONE_STATE missing).
  final int? simCount;

  factory PlatformCapabilities.fromMap(Map<Object?, Object?> m) =>
      PlatformCapabilities(
        platform: asString(m['platform']) ?? 'android',
        sdkInt: asInt(m['sdkInt']),
        manufacturer: asString(m['manufacturer']),
        model: asString(m['model']),
        hasTelephony: asBool(m['hasTelephony']),
        hasWifi: asBool(m['hasWifi']),
        hasGnss: asBool(m['hasGnss']),
        wifiEnabled: asBool(m['wifiEnabled']),
        simCount: asInt(m['simCount']),
      );
}
