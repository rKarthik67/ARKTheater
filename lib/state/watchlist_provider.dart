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
    _items = _newestFirst(await _service.load());
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
    final removed = List<MediaItem>.from(_items);
    _items = [];
    notifyListeners();
    await _service.save(const []);
    if (_shared) {
      for (final item in removed) {
        await _service.queuePendingChange(WatchlistPendingChange(
          operation: WatchlistChangeOperation.remove,
          item: item,
        ));
      }
      await _syncSilently();
    }
  }

  Future<void> toggle(MediaItem item) async {
    final exists = contains(item.type, item.id);
    final changedItem = exists
        ? _items.firstWhere((current) =>
            current.type == item.type && current.id == item.id)
        : item;
    if (exists) {
      _items.removeWhere((i) => i.type == item.type && i.id == item.id);
    } else {
      _items = [item.withWatchlistAddedAt(DateTime.now()), ..._items];
    }
    _items = _newestFirst(_items);
    notifyListeners();
    await _service.save(_items);
    if (_shared) {
      await _service.queuePendingChange(WatchlistPendingChange(
        operation: exists
            ? WatchlistChangeOperation.remove
            : WatchlistChangeOperation.add,
        item: changedItem,
      ));
      await _syncSilently();
    }
  }

  /// Creates a permanent SQLite-backed shared library from this device's
  /// current local titles, then begins receiving live change notifications.
  Future<WatchlistMergeResult> createSharedWatchlist() async {
    _setSyncing(true);
    try {
      final snapshot = await _sharedService.create(_items);
      _shared = true;
      final result = await _applySnapshot(snapshot);
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
      final result = await _applySnapshot(snapshot);
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
      await _deliverPendingChanges();
      final snapshot = await _sharedService.sync(_items);
      final result = await _applySnapshot(snapshot);
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

  Future<void> _deliverPendingChanges() async {
    final changes = await _service.loadPendingChanges();
    for (final change in changes) {
      final snapshot = change.operation == WatchlistChangeOperation.add
          ? await _sharedService.addItem(change.item)
          : await _sharedService.removeItem(change.item);
      await _service.removePendingChange(change);
      await _applySnapshot(snapshot);
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

  Future<WatchlistMergeResult> _applySnapshot(
    SharedWatchlistSnapshot snapshot,
  ) async {
    final deletedKeys = {
      for (final item in snapshot.deleted) '${item.type.name}:${item.id}',
    };
    final removedCount = _items.length;
    if (deletedKeys.isNotEmpty) {
      _items.removeWhere(
        (item) => deletedKeys.contains('${item.type.name}:${item.id}'),
      );
    }
    final hadRemovals = _items.length != removedCount;
    final result = await _mergeSnapshot(snapshot.items);
    if (hadRemovals) {
      await _service.save(_items);
      notifyListeners();
    }
    return result;
  }

  Future<WatchlistMergeResult> _mergeSnapshot(List<MediaItem> incoming) async {
    final toAdd = <MediaItem>[];
    var alreadyPresent = 0;
    var updatedExisting = false;
    for (final item in incoming) {
      final existingIndex = _items.indexWhere(
        (current) => current.type == item.type && current.id == item.id,
      );
      if (existingIndex >= 0) {
        alreadyPresent++;
        // SQLite is authoritative for when a title entered the shared
        // library. Replacing a device-local timestamp ensures every linked
        // device uses precisely the same newest-first order.
        if (item.watchlistAddedAt != null &&
            _items[existingIndex].watchlistAddedAt != item.watchlistAddedAt) {
          _items[existingIndex] = _items[existingIndex]
              .withWatchlistAddedAt(item.watchlistAddedAt!);
          updatedExisting = true;
        }
      } else if (!toAdd.any((i) => i.type == item.type && i.id == item.id)) {
        // Also de-dupes the incoming file against itself, in case the same
        // title appears twice in whatever was imported.
        toAdd.add(item);
      }
    }
    if (toAdd.isNotEmpty || updatedExisting) {
      _items = _newestFirst([...toAdd, ..._items]);
      notifyListeners();
      await _service.save(_items);
    }
    return WatchlistMergeResult(added: toAdd.length, alreadyPresent: alreadyPresent);
  }

  List<MediaItem> _newestFirst(List<MediaItem> items) {
    final indexed = items.indexed.toList();
    indexed.sort((a, b) {
      final aTime = a.$2.watchlistAddedAt?.millisecondsSinceEpoch ?? 0;
      final bTime = b.$2.watchlistAddedAt?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime) != 0
          ? bTime.compareTo(aTime)
          : _compareStableItems(a.$2, b.$2);
    });
    return indexed.map((entry) => entry.$2).toList();
  }

  int _compareStableItems(MediaItem first, MediaItem second) =>
      first.type.index.compareTo(second.type.index) != 0
          ? first.type.index.compareTo(second.type.index)
          : first.id.compareTo(second.id);
}

/// What happened when an imported watchlist was merged in - shown to the
/// user as e.g. "Added 12 new titles - 5 were already in your watchlist."
class WatchlistMergeResult {
  const WatchlistMergeResult({required this.added, required this.alreadyPresent});

  final int added;
  final int alreadyPresent;

  int get total => added + alreadyPresent;
}
