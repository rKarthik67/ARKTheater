import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../video_providers/common.dart';
import '../video_providers/names.dart';
import 'desktop_player_screen.dart';
import 'macos_player_screen.dart';
import 'mobile_player_screen.dart';

/// Playback entry point used everywhere else in the app (DetailScreen etc.)
/// - unchanged constructor shape from before this file was split. Picks the
/// actual player implementation per platform:
///
/// - Android/iOS: MobilePlayerScreen, built on better_player_plus (the same
///   ExoPlayer/AVPlayer engine flixquest itself uses) - see that file's doc
///   comment for why this matters for seek reliability on scraped sources.
/// - macOS: MacosPlayerScreen, built on video_player's AVPlayer backend -
///   the same underlying engine iOS uses, since media_kit/mpv was found to
///   hang indefinitely seeking on some scraped CDNs (see that file's doc
///   comment). better_player_plus itself has no macOS implementation, so
///   this is a different Flutter-side wrapper reaching the same engine.
/// - Windows/Linux: DesktopPlayerScreen, built on media_kit, since neither
///   better_player_plus nor video_player_avfoundation cover those platforms.
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

  // defaultTargetPlatform instead of dart:io's Platform - dart:io isn't
  // available on web, and the import alone fails a web compile even though
  // every use here is already behind !kIsWeb.
  bool get _usesMobileEngine =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _usesMacosEngine => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

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
    if (_usesMacosEngine) {
      return MacosPlayerScreen(
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
