import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';

/// A saved position paired with the duration it was saved against - lets a
/// caller (Home's Recently Watched row) show a "how far in" progress bar
/// without needing its own copy of the resume-position logic.
class PlaybackProgress {
  const PlaybackProgress({required this.position, required this.duration});

  final Duration position;
  final Duration duration;

  double get fraction {
    if (duration.inMilliseconds <= 0) return 0;
    final raw = position.inMilliseconds / duration.inMilliseconds;
    return raw.clamp(0.0, 1.0);
  }
}

/// Persists "where the user left off" per movie/episode, so reopening a
/// title resumes instead of always restarting at 0:00. This is deliberately
/// separate from RecentlyWatchedService, which only remembers *that* a
/// title was watched (for the Home row) - see that service's doc comment
/// for why it doesn't track position itself.
///
/// Both player screens (mobile and desktop) save into this periodically
/// during playback and read from it once, right after a new source finishes
/// loading.
class PlaybackPositionService {
  static const _key = 'ark_theater.playback_positions.v1';

  /// Saved spots older than this are dropped on the next write, so the
  /// stored map doesn't grow forever on a long-running install.
  static const _maxAge = Duration(days: 120);

  /// A title counts as "finished" once playback has passed this fraction of
  /// its duration - resuming with only the last minute or so left is more
  /// annoying than useful, so those don't get a saved spot at all.
  static const _finishedThreshold = 0.95;

  /// Positions under this are treated as "just started" - not worth
  /// persisting or resuming from.
  static const _minSaveable = Duration(seconds: 10);

  Future<Duration?> load({
    required MediaType mediaType,
    required int tmdbId,
    int? season,
    int? episode,
  }) async {
    final map = await _readMap();
    final entry = map[_entryKey(mediaType, tmdbId, season, episode)] as Map<String, dynamic>?;
    if (entry == null) return null;
    final seconds = (entry['positionSeconds'] as num?)?.toInt();
    if (seconds == null) return null;
    final position = Duration(seconds: seconds);
    return position >= _minSaveable ? position : null;
  }

  /// Same lookup as [load], but also returns the duration it was saved
  /// against so a caller can compute a watched fraction - entries saved
  /// before this field existed (just positionSeconds, no durationSeconds)
  /// return null here rather than a bogus 0% bar; they'll gain a duration
  /// automatically the next time that title is played for a few seconds.
  Future<PlaybackProgress?> loadProgress({
    required MediaType mediaType,
    required int tmdbId,
    int? season,
    int? episode,
  }) async {
    final map = await _readMap();
    final entry = map[_entryKey(mediaType, tmdbId, season, episode)] as Map<String, dynamic>?;
    if (entry == null) return null;
    final positionSeconds = (entry['positionSeconds'] as num?)?.toInt();
    final durationSeconds = (entry['durationSeconds'] as num?)?.toInt();
    if (positionSeconds == null || durationSeconds == null || durationSeconds <= 0) return null;
    return PlaybackProgress(
      position: Duration(seconds: positionSeconds),
      duration: Duration(seconds: durationSeconds),
    );
  }

  /// Called periodically during playback (every few seconds) and once more
  /// when the player closes. Silently does nothing (and returns false)
  /// until `duration` is known (e.g. before the source has finished
  /// opening). Returns true the moment this call finds the title "finished"
  /// (past the threshold below) - the player screens use that to also drop
  /// the title from Recently Watched, since a fully-watched title has
  /// nothing left to resume.
  Future<bool> save({
    required MediaType mediaType,
    required int tmdbId,
    int? season,
    int? episode,
    required Duration position,
    required Duration duration,
  }) async {
    if (duration <= Duration.zero || position < _minSaveable) return false;

    final map = await _readMap();
    final key = _entryKey(mediaType, tmdbId, season, episode);
    final fraction = position.inMilliseconds / duration.inMilliseconds;
    final finished = fraction >= _finishedThreshold;

    if (finished) {
      // Watched through (or close enough) - clear it so the next open
      // starts fresh instead of resuming three seconds from the end.
      map.remove(key);
    } else {
      map[key] = {
        'positionSeconds': position.inSeconds,
        'durationSeconds': duration.inSeconds,
        'savedAt': DateTime.now().toIso8601String(),
      };
    }

    _pruneStale(map);
    await _writeMap(map);
    return finished;
  }

  /// Explicitly clears a saved spot - not currently wired up to any UI
  /// action, but here for a future "remove from continue watching" button.
  Future<void> clear({
    required MediaType mediaType,
    required int tmdbId,
    int? season,
    int? episode,
  }) async {
    final map = await _readMap();
    map.remove(_entryKey(mediaType, tmdbId, season, episode));
    await _writeMap(map);
  }

  /// Forgets every saved resume position (Settings > Data & Storage).
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Future<Map<String, dynamic>> _readMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeMap(Map<String, dynamic> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(map));
  }

  void _pruneStale(Map<String, dynamic> map) {
    final cutoff = DateTime.now().subtract(_maxAge);
    map.removeWhere((_, value) {
      final savedAt = DateTime.tryParse((value as Map<String, dynamic>)['savedAt'] as String? ?? '');
      return savedAt == null || savedAt.isBefore(cutoff);
    });
  }

  /// Same movie-or-specific-episode identity RecentlyWatchedEntry uses, so
  /// a saved position lines up with the right season/episode later.
  String _entryKey(MediaType mediaType, int tmdbId, int? season, int? episode) =>
      '${mediaType.name}:$tmdbId:${season ?? ''}:${episode ?? ''}';
}
