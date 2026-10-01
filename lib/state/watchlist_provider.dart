import 'package:flutter/foundation.dart';
import '../models/media_item.dart';
import '../services/shared_watchlist_service.dart';
import '../services/watchlist_service.dart';

class WatchlistProvider extends ChangeNotifier {
  WatchlistProvider(this._service, {SharedWatchlistService? sharedService})
      : _sharedService = sharedService ?? SharedWatchlistService() {
    _load();
  }

  final WatchlistService _service;
  final SharedWatchlistService _sharedService;
  List<MediaItem> _items = [];
  bool _loaded = false;
  bool _shared = false;
  bool _syncing = false;
  String? _lastSyncError;

  List<MediaItem> get items => List.unmodifiable(_items);
  bool get isLoaded => _loaded;
  bool get isShared => _shared;
  bool get isSyncing => _syncing;
  String? get lastSyncError => _lastSyncError;

  bool contains(MediaType type, int id) =>
      _items.any((i) => i.type == type && i.id == id);

  Future<void> _load() async {
    _items = await _service.load();
    _loaded = true;
    notifyListeners();
    final secret = await _sharedService.readSecret();
    _shared = secret != null && secret.isNotEmpty;
    notifyListeners();
    if (_shared) {
      await _sharedService.startEvents(_syncFromEvent);
      await _syncSilently();
    }
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
    // The initial shared-watchlist release intentionally has add-only union
    // semantics. Removals stay local until a future synced-delete design is
    // introduced; a later union sync may restore an item another device has.
    if (_shared && !exists) await _syncSilently();
  }

  /// Creates a permanent SQLite-backed shared library from this device's
  /// current local titles, then begins receiving live change notifications.
  Future<WatchlistMergeResult> createSharedWatchlist() async {
    _setSyncing(true);
    try {
      final snapshot = await _sharedService.create(_items);
      _shared = true;
      final result = await _mergeSnapshot(snapshot.items);
      await _sharedService.startEvents(_syncFromEvent);
      _lastSyncError = null;
      return result;
    } catch (error) {
      _lastSyncError = '$error';
      rethrow;
    } finally {
      _setSyncing(false);
    }
  }

  /// Claims a four-digit, one-use pairing code and merges both devices into
  /// the same long-lived library.
  Future<WatchlistMergeResult> joinSharedWatchlist(String code) async {
    _setSyncing(true);
    try {
      final snapshot = await _sharedService.join(code, _items);
      _shared = true;
      final result = await _mergeSnapshot(snapshot.items);
      await _sharedService.startEvents(_syncFromEvent);
      _lastSyncError = null;
      return result;
    } catch (error) {
      _lastSyncError = '$error';
      rethrow;
    } finally {
      _setSyncing(false);
    }
  }

  Future<PairingCode> createPairingCode() => _sharedService.createPairingCode();

  /// Reads the server's authoritative union and contributes any local titles
  /// the server has not seen. This is also the recovery path after offline
  /// use or a missed live event.
  Future<WatchlistMergeResult> syncNow() async {
    if (!_shared) throw const SharedWatchlistException('This device is not connected to a shared watchlist.');
    if (_syncing) return const WatchlistMergeResult(added: 0, alreadyPresent: 0);
    _setSyncing(true);
    try {
      final snapshot = await _sharedService.sync(_items);
      final result = await _mergeSnapshot(snapshot.items);
      _lastSyncError = null;
      return result;
    } catch (error) {
      _lastSyncError = '$error';
      rethrow;
    } finally {
      _setSyncing(false);
    }
  }

  /// Stops using the remote library on only this device. The shared library
  /// and its titles stay intact for other linked devices.
  Future<void> disconnectSharedWatchlist() async {
    await _sharedService.disconnect();
    _shared = false;
    _lastSyncError = null;
    notifyListeners();
  }

  Future<void> _syncFromEvent() async {
    if (!_shared || _syncing) return;
    await _syncSilently();
  }

  Future<void> _syncSilently() async {
    try {
      await syncNow();
    } catch (_) {
      // The manual Sync now control exposes the failure. Local bookmarks stay
      // available and the next event/app launch retries automatically.
    }
  }

  void _setSyncing(bool value) {
    _syncing = value;
    notifyListeners();
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
    return _mergeSnapshot(incoming);
  }

  Future<WatchlistMergeResult> _mergeSnapshot(List<MediaItem> incoming) async {
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
