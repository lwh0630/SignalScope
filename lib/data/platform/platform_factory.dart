import 'dart:io';

import 'android_platform.dart';
import 'signal_platform.dart';
import 'unsupported_platform.dart';

/// Chooses the platform adapter for the current host.
SignalPlatform createSignalPlatform() {
  if (Platform.isAndroid) return AndroidPlatform();
  return UnsupportedPlatform(Platform.operatingSystem);
}
