import 'package:shared_preferences/shared_preferences.dart';

/// Local list of past search terms - shown when the search field is empty,
/// mirroring flixquest's recent-searches list (tap a term to search again,
/// or clear all).
class RecentSearchesService {
  static const _key = 'ark_theater.recent_searches.v1';
  static const _maxEntries = 12;

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  Future<void> add(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    list.removeWhere((q) => q.toLowerCase() == trimmed.toLowerCase());
    list.insert(0, trimmed);
    await prefs.setStringList(_key, list.take(_maxEntries).toList());
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
