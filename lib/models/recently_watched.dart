import 'media_item.dart';

/// One "recently watched" entry - recorded the moment a stream is
/// successfully resolved and about to play (see DetailScreen._play), not
/// tied to an on-device playback position the way flixquest's SQLite-backed
/// continue-watching is. Simpler, and works identically across both player
/// engines (media_kit on desktop, better_player_plus on mobile) without
/// hooking into either one's position tracking.
class RecentlyWatchedEntry {
  final MediaItem item;
  final int? season;
  final int? episode;
  final DateTime watchedAt;

  const RecentlyWatchedEntry({
    required this.item,
    this.season,
    this.episode,
    required this.watchedAt,
  });

  /// Identity for de-duping/re-ordering - the same title+episode counts as
  /// the same entry, so re-watching just bumps it back to the front instead
  /// of creating a duplicate row entry.
  String get key => '${item.type.name}:${item.id}:${season ?? ''}:${episode ?? ''}';
}
