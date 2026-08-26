import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';
import '../models/recently_watched.dart';

/// Local-only "recently watched" history, capped to the most recent 20
/// entries - shown as a Home row. See RecentlyWatchedEntry for why this is
/// simpler than flixquest's position-tracking continue-watching.
class RecentlyWatchedService {
  static const _key = 'ark_theater.recently_watched.v1';
  static const _maxEntries = 20;

  Future<List<RecentlyWatchedEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => _fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> record({required MediaItem item, int? season, int? episode}) async {
    final entries = await load();
    final newEntry = RecentlyWatchedEntry(
      item: item,
      season: season,
      episode: episode,
      watchedAt: DateTime.now(),
    );
    entries.removeWhere((e) => e.key == newEntry.key);
    entries.insert(0, newEntry);
    final trimmed = entries.take(_maxEntries).toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(trimmed.map(_toJson).toList()));
  }

  /// Removes every entry for this title (any season/episode) - used by the
  /// "x" button on Home's Recently Watched row.
  Future<void> removeItem(MediaType type, int id) async {
    final entries = await load();
    entries.removeWhere((e) => e.item.type == type && e.item.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(entries.map(_toJson).toList()));
  }

  Map<String, dynamic> _toJson(RecentlyWatchedEntry e) => {
        'id': e.item.id,
        'type': e.item.type.name,
        'title': e.item.title,
        'posterPath': e.item.posterPath,
        'backdropPath': e.item.backdropPath,
        'voteAverage': e.item.voteAverage,
        'releaseDate': e.item.releaseDate,
        'season': e.season,
        'episode': e.episode,
        'watchedAt': e.watchedAt.toIso8601String(),
      };

  RecentlyWatchedEntry _fromJson(Map<String, dynamic> json) => RecentlyWatchedEntry(
        item: MediaItem(
          id: json['id'] as int,
          type: json['type'] == 'movie' ? MediaType.movie : MediaType.tv,
          title: json['title'] as String? ?? '',
          posterPath: json['posterPath'] as String?,
          backdropPath: json['backdropPath'] as String?,
          voteAverage: (json['voteAverage'] as num?)?.toDouble() ?? 0,
          releaseDate: json['releaseDate'] as String?,
        ),
        season: json['season'] as int?,
        episode: json['episode'] as int?,
        watchedAt: DateTime.tryParse(json['watchedAt'] as String? ?? '') ?? DateTime.now(),
      );
}
