import 'package:flutter/foundation.dart';
import '../models/media_item.dart';
import '../services/watchlist_service.dart';

class WatchlistProvider extends ChangeNotifier {
  WatchlistProvider(this._service) {
    _load();
  }

  final WatchlistService _service;
  List<MediaItem> _items = [];
  bool _loaded = false;

  List<MediaItem> get items => List.unmodifiable(_items);
  bool get isLoaded => _loaded;

  bool contains(MediaType type, int id) =>
      _items.any((i) => i.type == type && i.id == id);

  Future<void> _load() async {
    _items = await _service.load();
    _loaded = true;
    notifyListeners();
  }

  /// Empties the whole watchlist in one go (Settings > Data & Storage).
  Future<void> clearAll() async {
    _items = [];
    notifyListeners();
    await _service.save(const []);
  }

  Future<void> toggle(MediaItem item) async {
    final exists = contains(item.type, item.id);
    if (exists) {
      _items.removeWhere((i) => i.type == item.type && i.id == item.id);
    } else {
      _items = [item, ..._items];
    }
    notifyListeners();
    await _service.save(_items);
  }

  /// The JSON text for "Export Watchlist" (Settings > Library) - the
  /// current watchlist, in the format [WatchlistBackupService.import]
  /// (via [importAndMerge]) knows how to read back on another device.
  String exportJson() => _service.exportJson(_items);

  /// Parses a file picked for "Import Watchlist" into a list of
  /// items ready for [importAndMerge] - kept on the provider so the
  /// Settings screen only ever talks to WatchlistProvider, never
  /// WatchlistService directly. Rethrows [FormatException] as-is; its
  /// message is safe to show the user.
  List<MediaItem> parseImportJson(String raw) => _service.parseImportJson(raw);

  /// Merges an imported watchlist into the one already on this device,
  /// per Settings > Library > "Import Watchlist": anything already here
  /// (matched by TMDB id + media type, the same key [contains] uses) stays
  /// as the single existing entry; anything from the import that's missing
  /// here gets added. Nothing already on this device is ever removed by an
  /// import. Newly-added titles are placed at the front, same as a fresh
  /// [toggle] add, so they show up first in the watchlist right after
  /// importing. Returns how many titles were newly added vs. already
  /// present, so the caller can tell the user what actually changed.
  Future<WatchlistMergeResult> importAndMerge(List<MediaItem> incoming) async {
    final toAdd = <MediaItem>[];
    var alreadyPresent = 0;
    for (final item in incoming) {
      if (contains(item.type, item.id)) {
        alreadyPresent++;
      } else if (!toAdd.any((i) => i.type == item.type && i.id == item.id)) {
        // Also de-dupes the incoming file against itself, in case the same
        // title appears twice in whatever was imported.
        toAdd.add(item);
      }
    }
    if (toAdd.isNotEmpty) {
      _items = [...toAdd, ..._items];
      notifyListeners();
      await _service.save(_items);
    }
    return WatchlistMergeResult(added: toAdd.length, alreadyPresent: alreadyPresent);
  }
}

/// What happened when an imported watchlist was merged in - shown to the
/// user as e.g. "Added 12 new titles - 5 were already in your watchlist."
class WatchlistMergeResult {
  const WatchlistMergeResult({required this.added, required this.alreadyPresent});

  final int added;
  final int alreadyPresent;

  int get total => added + alreadyPresent;
}
