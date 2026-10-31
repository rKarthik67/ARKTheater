import 'package:flutter/material.dart';
import '../core/responsive.dart';
import '../core/theme.dart';
import 'liquid_glass.dart';

class NavDestinationSpec {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const NavDestinationSpec({required this.icon, required this.selectedIcon, required this.label});
}

/// One navigation shell that becomes a bottom nav bar on phones, tablets,
/// iPad and desktop, and a side navigation rail only on Android TV/Fire TV.
///
/// This is a remote-vs-touch split, not a screen-size split: an iPad and a
/// Fire TV plugged into a TV can report the same width, but only the TV is
/// driven by a D-pad, which is exactly where a rail down the left edge
/// earns its keep - everywhere else (including large tablets/desktop) a
/// bottom bar is the more natural, reachable placement, so it's used
/// everywhere Responsive.isTv is false. See Responsive.isTv/initDeviceType
/// for how the TV/Fire TV check itself works.
class ResponsiveScaffold extends StatelessWidget {
  const ResponsiveScaffold({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    this.floatingActionButton,
  });

  final List<NavDestinationSpec> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final isTv = Responsive.isTv;

    if (!isTv) {
      // On phones the bar naturally reads as roughly full-width already
      // (16px side padding on a ~360-420px screen). On tablets/iPad and
      // desktop the same 16px padding would leave it stretched almost
      // edge-to-edge across a much wider screen, which doesn't match how
      // iPadOS/macOS-style bottom bars are usually presented - so on those
      // wider layouts it's capped to a comfortable width and centered
      // instead, floating like a dock rather than spanning the screen.
      final isWide = Responsive.isTablet(context) || Responsive.isDesktop(context);

      final navBar = LiquidGlass(
        borderRadius: BorderRadius.circular(26),
        // BottomNavigationBar has no direct height property - its
        // default (icon + always-on label + built-in vertical padding)
        // runs close to 80px, which read as oversized against the
        // slimmer glass pill. Constraining it with a SizedBox and
        // trimming the icon/label sizes to match brings it down to a
        // more native-feeling ~58px without clipping.
        //
        // selectedItemColor/unselectedItemColor are passed directly here
        // (rather than through a Theme override) so both the icon AND
        // label pick up an explicit, clearly-different color for each
        // state - important now that the glass itself is much more
        // transparent, so whatever's scrolling behind the bar can no
        // longer be relied on for contrast.
        child: SizedBox(
          height: 58,
          child: BottomNavigationBar(
            currentIndex: selectedIndex,
            onTap: onDestinationSelected,
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconSize: 22,
            selectedFontSize: 11,
            unselectedFontSize: 10,
            selectedItemColor: Theme.of(context).colorScheme.primary,
            unselectedItemColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.72),
            items: [
              for (final d in destinations)
                BottomNavigationBarItem(icon: Icon(d.icon), activeIcon: Icon(d.selectedIcon), label: d.label),
            ],
          ),
        ),
      );

      return Scaffold(
        body: body,
        floatingActionButton: floatingActionButton,
        extendBody: true,
        // Persistent chrome shouldn't jump around to dodge the keyboard
        // (each screen's own inner Scaffold already handles its text
        // fields), and pinning this to false also makes the bar immune to
        // bogus bottom insets some emulators report with
        // android:windowSoftInputMode="adjustResize".
        resizeToAvoidBottomInset: false,
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: isWide
              // heightFactor: 1.0 is load-bearing, not decoration. Scaffold
              // lays its bottomNavigationBar out with LOOSE constraints
              // whose maxHeight is the whole screen, and a bare Center
              // (Align) expands to fill any bounded height it's given. That
              // made this slot the full height of the screen and centred the
              // 58px pill inside it - i.e. floating in the dead middle of the
              // display rather than sitting at the bottom edge. Pinning
              // heightFactor to 1.0 makes it shrink-wrap the pill's real
              // height so the slot stays 58px and Scaffold can park it at the
              // bottom, while the horizontal centering still works.
              ? Center(
                  heightFactor: 1.0,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: navBar,
                  ),
                )
              : navBar,
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
            child: LiquidGlass(
              borderRadius: BorderRadius.circular(24),
              child: NavigationRail(
                backgroundColor: Colors.transparent,
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
                labelType: NavigationRailLabelType.all,
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: FlutterLogoOrBrand(),
                ),
                destinations: [
                  for (final d in destinations)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
                    ),
                ],
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}

class FlutterLogoOrBrand extends StatelessWidget {
  const FlutterLogoOrBrand({super.key});

  @override
  Widget build(BuildContext context) {
    // The "A" emblem cropped out of the full ARK Theatre logo (see
    // assets/images/splash_logo1.png, the full lockup used on the splash
    // screen) - just the mark, no wordmark, since the full lockup is
    // illegible at nav-rail-icon size. Both are true-alpha transparent PNGs
    // so they sit on the LiquidGlass nav surface without a background box.
    return Image.asset(
      'assets/images/logo_mark_icon.png',
      width: 36,
      height: 36,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) =>
          Icon(Icons.local_movies, color: AppTheme.resolvedAccent(context), size: 32),
    );
  }
}
