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

/// One navigation shell that becomes a bottom nav bar on phones, and a
/// side navigation rail on tablets/desktop - the same pattern the reference
/// web app gets "for free" from a responsive Header, done natively here.
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
    final isCompact = Responsive.isMobile(context);

    if (isCompact) {
      return Scaffold(
        body: body,
        floatingActionButton: floatingActionButton,
        extendBody: true,
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: LiquidGlass(
            borderRadius: BorderRadius.circular(28),
            child: BottomNavigationBar(
              currentIndex: selectedIndex,
              onTap: onDestinationSelected,
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.transparent,
              elevation: 0,
              items: [
                for (final d in destinations)
                  BottomNavigationBarItem(icon: Icon(d.icon), activeIcon: Icon(d.selectedIcon), label: d.label),
              ],
            ),
          ),
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
          const Icon(Icons.local_movies, color: AppTheme.accent, size: 32),
    );
  }
}
