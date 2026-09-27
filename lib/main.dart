import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'core/responsive.dart';
import 'services/recently_watched_service.dart';
import 'services/watchlist_service.dart';
import 'state/recently_watched_provider.dart';
import 'state/settings_provider.dart';
import 'state/watchlist_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Detects Android TV / Fire TV once at startup (see
  // Responsive.initDeviceType()'s doc comment) so ResponsiveScaffold can
  // read Responsive.isTv synchronously in every build() from here on -
  // it decides the side NavigationRail (TV, remote-driven) vs. bottom
  // nav bar (phones/tablets/desktop) split.
  await Responsive.initDeviceType();

  // Loads API keys from .env. Stream-source selection is stored separately
  // in Settings so it can safely switch between the two supported servers.
  try {
    await dotenv.load(fileName: '.env');
    // ignore: avoid_print
    print('[ARKTheater] .env loaded OK.');
  } catch (err) {
    // ignore: avoid_print
    print('[ARKTheater] .env FAILED TO LOAD: ' + err.toString() + ' (falling back to AppConfig defaults)');
    dotenv.testLoad(fileInput: '');
  }

  // Registers media_kit's native playback backends for every platform.
  MediaKit.ensureInitialized();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WatchlistProvider(WatchlistService())),
        ChangeNotifierProvider(create: (_) => RecentlyWatchedProvider(RecentlyWatchedService())),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: const ArkTheaterApp(),
    ),
  );
}
