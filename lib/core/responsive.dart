import 'package:flutter/widgets.dart';

/// Breakpoints shared across the app so mobile, tablet, desktop, and iPad
/// layouts stay consistent wherever they're checked from.
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

  /// How many poster cards fit a row at the current width; used by grids and
  /// horizontal carousels so they feel native on everything from a phone to
  /// an ultrawide desktop window.
  static int gridColumns(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1600) return 8;
    if (width >= desktopBreakpoint) return 6;
    if (width >= tabletBreakpoint) return 4;
    if (width >= 420) return 3;
    return 2;
  }
}
