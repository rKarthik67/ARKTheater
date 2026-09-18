import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'models/media_item.dart';
import 'screens/detail_screen.dart';
import 'screens/home_screen.dart';
import 'screens/movies_screen.dart';
import 'screens/platforms_screen.dart';
import 'screens/search_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/tvshows_screen.dart';
import 'widgets/responsive_scaffold.dart';

class ArkTheaterApp extends StatelessWidget {
  const ArkTheaterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ARKTheater',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const SplashScreen(next: _RootShell()),
    );
  }
}

class _RootShell extends StatefulWidget {
  const _RootShell();

  @override
  State<_RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<_RootShell> {
  int _index = 0;

  void _openDetail(MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailScreen(item: item, onSelectRelated: _openDetail),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Order matches the bottom nav / rail: Home, Movies, TV Shows,
    // Platforms, Search, Settings. The watchlist used to have its own
    // tab here; it now lives inside Settings instead (first list tile).
    final pages = [
      HomeScreen(onSelect: _openDetail),
      MoviesScreen(onSelect: _openDetail),
      TVShowsScreen(onSelect: _openDetail),
      PlatformsScreen(onSelect: _openDetail),
      SearchScreen(onSelect: _openDetail),
      SettingsScreen(onSelect: _openDetail),
    ];

    return ResponsiveScaffold(
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
      destinations: const [
        NavDestinationSpec(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
        NavDestinationSpec(icon: Icons.movie_outlined, selectedIcon: Icons.movie, label: 'Movies'),
        NavDestinationSpec(icon: Icons.live_tv_outlined, selectedIcon: Icons.live_tv, label: 'TV Shows'),
        NavDestinationSpec(icon: Icons.apps_outlined, selectedIcon: Icons.apps, label: 'Platforms'),
        NavDestinationSpec(icon: Icons.search_outlined, selectedIcon: Icons.search, label: 'Search'),
        NavDestinationSpec(
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings,
          label: 'Settings',
        ),
      ],
      body: IndexedStack(index: _index, children: pages),
    );
  }
}
