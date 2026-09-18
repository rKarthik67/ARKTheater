import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum DeviceClass { mobile, tablet, desktop }

class Responsive {
  Responsive._();

  static const double tabletBreakpoint = 600;
  static const double desktopBreakpoint = 1024;

  static DeviceClass classify(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= desktopBreakpoint) return DeviceClass.desktop;
    if (width >= tabletBreakpoint) return DeviceClass.tablet;
    return DeviceClass.mobile;
  }

  static bool isMobile(BuildContext context) => classify(context) == DeviceClass.mobile;
  static bool isTablet(BuildContext context) => classify(context) == DeviceClass.tablet;
  static bool isDesktop(BuildContext context) => classify(context) == DeviceClass.desktop;

  static int gridColumns(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1600) return 8;
    if (width >= desktopBreakpoint) return 6;
    if (width >= tabletBreakpoint) return 4;
    if (width >= 420) return 3;
    return 2;
  }

  // --- Android TV / Fire TV detection -------------------------------------
  //
  // Nav placement isn't a screen-WIDTH question the way grid density is: a
  // phone, an iPad, and a Fire TV plugged into a 55" TV can all report a
  // "tablet" or "desktop"-sized width, but only the TV is driven by a D-pad
  // remote instead of touch, and only the TV actually benefits from a rail
  // down the left edge. So this is tracked separately from [classify].
  //
  // [isTv] defaults to false and is set once at startup by
  // [initDeviceType], which main() awaits before runApp(). After that it
  // can be read synchronously anywhere (widget build() methods are
  // synchronous, so a per-build platform-channel call isn't an option).
  static bool isTv = false;

  static const MethodChannel _deviceTypeChannel = MethodChannel('ark_theater/device_type');

  /// Asks MainActivity.kt whether this device reports the Android TV
  /// "Leanback" system feature (true for both Google Android TV and Amazon
  /// Fire TV/Firestick - see MainActivity.kt's doc comment for why one
  /// check covers both). No-ops (leaves [isTv] false) on any non-Android
  /// platform, and on any error talking to the platform channel, so a
  /// missing/failed channel never blocks app startup.
  static Future<void> initDeviceType() async {
    if (!Platform.isAndroid) return;
    try {
      final result = await _deviceTypeChannel.invokeMethod<bool>('isTv');
      isTv = result ?? false;
    } catch (_) {
      isTv = false;
    }
  }
}
