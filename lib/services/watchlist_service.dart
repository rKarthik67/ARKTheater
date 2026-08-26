import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';

/// Local-only watchlist persistence (no account system per current scope).
/// Mirrors the reference web app's `watchlistStorage.js`, backed by
/// SharedPreferences so it works identically on mobile, tablet, and desktop.
class WatchlistService {
  static const _key = 'ark_theater.watchlist.v1';

  Future<List<MediaItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => _fromStorageJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> save(List<MediaItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(items.map(_toStorageJson).toList());
    await prefs.setString(_key, raw);
  }

  Map<String, dynamic> _toStorageJson(MediaItem item) => {
        'id': item.id,
        'type': item.type.name,
        'title': item.title,
        'posterPath': item.posterPath,
        'voteAverage': item.voteAverage,
        'releaseDate': item.releaseDate,
      };

  MediaItem _fromStorageJson(Map<String, dynamic> json) => MediaItem(
        id: json['id'] as int,
        type: json['type'] == 'movie' ? MediaType.movie : MediaType.tv,
        title: json['title'] as String? ?? '',
        posterPath: json['posterPath'] as String?,
        voteAverage: (json['voteAverage'] as num?)?.toDouble() ?? 0,
        releaseDate: json['releaseDate'] as String?,
      );
}
