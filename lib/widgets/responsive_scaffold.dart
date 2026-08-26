import 'package:flutter/material.dart';
import '../core/responsive.dart';
import '../core/theme.dart';

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
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: selectedIndex,
          onTap: onDestinationSelected,
          type: BottomNavigationBarType.fixed,
          items: [
            for (final d in destinations)
              BottomNavigationBarItem(icon: Icon(d.icon), activeIcon: Icon(d.selectedIcon), label: d.label),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: AppTheme.surface,
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
          const VerticalDivider(width: 1, color: Colors.white12),
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
    // assets/images/splash_logo.png) - just the mark, no wordmark, since
    // the full lockup is illegible at nav-rail-icon size.
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        'assets/images/logo_mark.png',
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.local_movies, color: AppTheme.accent, size: 32),
      ),
    );
  }
}
