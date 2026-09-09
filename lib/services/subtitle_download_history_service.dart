import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';

/// Tracks which external (Wyzie) subtitle files the user has picked, per
/// title/episode - keyed the same way PlaybackPositionService and
/// RecentlyWatchedEntry are ('$mediaType:$tmdbId:$season:$episode'), so
/// once that specific episode/movie is fully finished, the subtitles
/// downloaded for it can be forgotten too (see clearForMedia) instead of
/// hanging around forever.
///
/// Subtitles are identified by Wyzie's own `id` field, not the download
/// `url` - Wyzie's docs describe `id` as "the ID of the subtitle file"
/// versus `url` as just "the URL to the subtitle file", and some of
/// Wyzie's underlying sources hand back URLs carrying a verification
/// token that isn't guaranteed identical between two separate searches
/// for the same file, so `id` is the value actually safe to compare.
class SubtitleDownloadHistoryService {
  static const _mapKey = 'ark_theater.downloaded_subtitle_ids_by_media.v2';
  static const _lastIdKey = 'ark_theater.last_downloaded_subtitle_id.v2';

  // Per title/episode - only the most recent picks for that one episode
  // are worth remembering.
  static const _maxIdsPerMedia = 50;

  String _mediaKey(MediaType mediaType, int tmdbId, int? season, int? episode) =>
      '${mediaType.name}:$tmdbId:${season ?? ''}:${episode ?? ''}';

  Future<Map<String, dynamic>> _readMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_mapKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeMap(Map<String, dynamic> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mapKey, jsonEncode(map));
  }

  /// Every subtitle id picked for any title/episode still tracked - used
  /// to highlight "you've picked this one before" in the search sheet. A
  /// subtitle shared across more than one episode/movie (same file
  /// happens to match both) stays highlighted for the others even after
  /// one of those episodes finishes and is cleared.
  Future<Set<String>> loadDownloadedIds() async {
    final map = await _readMap();
    final ids = <String>{};
    for (final value in map.values) {
      if (value is List) ids.addAll(value.map((e) => e.toString()));
    }
    return ids;
  }

  /// The single most recently picked subtitle id, across every title -
  /// used for the distinct "Last downloaded" highlight.
  Future<String?> loadLastDownloadedId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastIdKey);
  }

  Future<void> markDownloaded({
    required MediaType mediaType,
    required int tmdbId,
    int? season,
    int? episode,
    required String subtitleId,
  }) async {
    if (subtitleId.isEmpty) return;
    final map = await _readMap();
    final key = _mediaKey(mediaType, tmdbId, season, episode);
    final list = ((map[key] as List?) ?? const []).map((e) => e.toString()).toList();
    list.remove(subtitleId); // de-dupe, then re-add at the end (most-recent-last)
    list.add(subtitleId);
    map[key] = list.length > _maxIdsPerMedia ? list.sublist(list.length - _maxIdsPerMedia) : list;
    await _writeMap(map);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastIdKey, subtitleId);
  }

  /// Called once a title/episode is fully finished (the same "finished"
  /// signal PlaybackPositionService.save() returns, already used to drop
  /// it from Recently Watched) - forgets which subtitles were downloaded
  /// for THAT episode specifically, so they stop showing as "already
  /// downloaded" once you're done with it. A subtitle id also downloaded
  /// for a different, still-unfinished episode stays tracked there.
  Future<void> clearForMedia({
    required MediaType mediaType,
    required int tmdbId,
    int? season,
    int? episode,
  }) async {
    final map = await _readMap();
    final key = _mediaKey(mediaType, tmdbId, season, episode);
    if (map.remove(key) != null) {
      await _writeMap(map);
    }
  }
}
