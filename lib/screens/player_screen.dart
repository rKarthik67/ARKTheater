import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../video_providers/common.dart';
import '../video_providers/names.dart';
import 'desktop_player_screen.dart';
import 'mobile_player_screen.dart';

/// Playback entry point used everywhere else in the app (DetailScreen etc.)
/// - unchanged constructor shape from before this file was split. Picks the
/// actual player implementation per platform:
///
/// - Android/iOS: MobilePlayerScreen, built on better_player_plus (the same
///   ExoPlayer/AVPlayer engine flixquest itself uses) - see that file's doc
///   comment for why this matters for seek reliability on scraped sources.
/// - Windows/macOS/Linux: DesktopPlayerScreen, built on media_kit, since
///   better_player_plus has no desktop support at all.
class PlayerScreen extends StatelessWidget {
  const PlayerScreen({
    super.key,
    required this.title,
    required this.mediaType,
    required this.tmdbId,
    this.season,
    this.episode,
    required this.providers,
    required this.initialProviderIndex,
    required this.initialResult,
  });

  final String title;
  final MediaType mediaType;
  final int tmdbId;
  final int? season;
  final int? episode;
  final List<VideoProvider> providers;
  final int initialProviderIndex;
  final ProviderLoadResult initialResult;

  bool get _usesMobileEngine =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Widget build(BuildContext context) {
    if (_usesMobileEngine) {
      return MobilePlayerScreen(
        title: title,
        mediaType: mediaType,
        tmdbId: tmdbId,
        season: season,
        episode: episode,
        providers: providers,
        initialProviderIndex: initialProviderIndex,
        initialResult: initialResult,
      );
    }
    return DesktopPlayerScreen(
      title: title,
      mediaType: mediaType,
      tmdbId: tmdbId,
      season: season,
      episode: episode,
      providers: providers,
      initialProviderIndex: initialProviderIndex,
      initialResult: initialResult,
    );
  }
}
