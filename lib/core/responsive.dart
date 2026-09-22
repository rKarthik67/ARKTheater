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

  /// Vertical space the floating bottom nav bar covers, for any scrollable
  /// that sits behind it to pad its content by.
  ///
  /// ResponsiveScaffold sets `extendBody: true`, so body content genuinely
  /// runs *underneath* the glass nav bar rather than stopping above it -
  /// that's what makes the blur have something to blur. The cost is that
  /// the last thing in a scroll view (a "Load more" button, the final row
  /// of a grid) ends up behind the bar, where it's both hard to read and
  /// impossible to tap, because the bar is painted on top and eats the
  /// touch. Padding the scroll view's bottom by this much lets that last
  /// element scroll clear of the bar instead.
  ///
  /// Made up of the bar's own height (58) + its bottom margin (10) + a
  /// little breathing room (12), plus whatever the system reserves at the
  /// bottom (gesture bar / soft keys). Returns 0 on TV, where navigation
  /// is a rail down the left edge and nothing overlaps the bottom.
  static double bottomNavInset(BuildContext context) {
    if (isTv) return 0;
    return 80 + MediaQuery.paddingOf(context).bottom;
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
    // defaultTargetPlatform rather than dart:io's Platform: dart:io does
    // not exist on web at all, and merely importing it breaks a web
    // compile even behind a runtime guard.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final result = await _deviceTypeChannel.invokeMethod<bool>('isTv');
      isTv = result ?? false;
    } catch (_) {
      isTv = false;
    }
  }
}
