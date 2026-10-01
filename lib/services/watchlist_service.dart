import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';

/// Local-only watchlist persistence (no account system per current scope).
/// Mirrors the reference web app's `watchlistStorage.js`, backed by
/// SharedPreferences so it works identically on mobile, tablet, and desktop.
///
/// Also handles the JSON shape used by Settings > Library's "Export
/// Watchlist" / "Import Watchlist" - a small versioned envelope around the
/// same per-item fields already persisted locally, so a watchlist can be
/// shared to another device (AirDrop, Messages, email, a cloud drive, etc.)
/// and merged back in there. The actual file I/O (share sheet / file
/// picker) lives in WatchlistBackupService - this class only knows how to
/// turn a list of items into JSON and back.
class WatchlistService {
  static const _key = 'ark_theater.watchlist.v1';
  static const _pendingChangesKey = 'ark_theater.watchlist.pending_changes.v1';

  /// Bumped only if the exported shape changes in a way older parseImportJson
  /// logic couldn't already handle - parseImportJson doesn't currently
  /// branch on this, since the per-item fields have been stable since v1.
  static const _exportFormatVersion = 1;

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

  /// Keeps explicit shared-library actions until the device can deliver them.
  /// A full-list sync is intentionally unable to infer a deletion, so queued
  /// actions are what make an offline remove/re-add replicate later.
  Future<List<WatchlistPendingChange>> loadPendingChanges() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingChangesKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final changes = <WatchlistPendingChange>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final operation = entry['operation'];
        final item = entry['item'];
        if (operation is! String || item is! Map) continue;
        if (operation != WatchlistChangeOperation.add.name &&
            operation != WatchlistChangeOperation.remove.name) {
          continue;
        }
        changes.add(WatchlistPendingChange(
          operation: operation == WatchlistChangeOperation.add.name
              ? WatchlistChangeOperation.add
              : WatchlistChangeOperation.remove,
          item: _fromStorageJson(Map<String, dynamic>.from(item)),
        ));
      }
      return changes;
    } catch (_) {
      return const [];
    }
  }

  Future<void> queuePendingChange(WatchlistPendingChange change) async {
    final changes = await loadPendingChanges();
    // Only the latest local action for one title matters before the next sync.
    final merged = <String, WatchlistPendingChange>{
      for (final current in changes) current.key: current,
      change.key: change,
    };
    await _savePendingChanges(merged.values.toList());
  }

  Future<void> removePendingChange(WatchlistPendingChange change) async {
    final changes = await loadPendingChanges();
    await _savePendingChanges(changes.where((current) => current.key != change.key).toList());
  }

  Future<void> _savePendingChanges(List<WatchlistPendingChange> changes) async {
    final prefs = await SharedPreferences.getInstance();
    if (changes.isEmpty) {
      await prefs.remove(_pendingChangesKey);
      return;
    }
    await prefs.setString(
      _pendingChangesKey,
      jsonEncode(changes.map((change) => {
            'operation': change.operation.name,
            'item': _toStorageJson(change.item),
          }).toList()),
    );
  }

  /// Builds the pretty-printed JSON text written to the exported file - a
  /// small envelope (app/version/exportedAt/items) rather than a bare
  /// array, so a future format change can still recognize and migrate an
  /// older export instead of guessing what a plain list of objects is.
  String exportJson(List<MediaItem> items) {
    final envelope = {
      'app': 'ARKTheater',
      'export': 'watchlist',
      'version': _exportFormatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'items': items.map(_toStorageJson).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  /// Parses a watchlist JSON file picked for "Import Watchlist". Accepts
  /// both this app's own envelope (`{"items": [...]}`) and a bare `[...]`
  /// array, so a hand-edited or older-format file still imports instead of
  /// erroring. A row that doesn't parse (missing/malformed id, etc.) is
  /// skipped rather than failing the whole import.
  ///
  /// Throws a [FormatException] - with a message safe to show the user
  /// directly - if the file isn't recognizable watchlist JSON at all.
  List<MediaItem> parseImportJson(String raw) {
    final dynamic decoded = jsonDecode(raw);
    final List rawItems;
    if (decoded is List) {
      rawItems = decoded;
    } else if (decoded is Map && decoded['items'] is List) {
      rawItems = decoded['items'] as List;
    } else {
      throw const FormatException("This file doesn't look like an ARKTheater watchlist export.");
    }

    final items = <MediaItem>[];
    for (final entry in rawItems) {
      if (entry is! Map) continue;
      try {
        items.add(_fromStorageJson(entry as Map<String, dynamic>));
      } catch (_) {
        // Skip one malformed row rather than failing the whole import.
      }
    }
    if (items.isEmpty && rawItems.isNotEmpty) {
      throw const FormatException('None of the rows in this file could be read as watchlist titles.');
    }
    return items;
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

enum WatchlistChangeOperation { add, remove }

class WatchlistPendingChange {
  const WatchlistPendingChange({required this.operation, required this.item});

  final WatchlistChangeOperation operation;
  final MediaItem item;

  String get key => '${item.type.name}:${item.id}';
}
