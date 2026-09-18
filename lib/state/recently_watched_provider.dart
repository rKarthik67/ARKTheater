import 'package:flutter/foundation.dart';
import '../models/media_item.dart';
import '../models/recently_watched.dart';
import '../services/recently_watched_service.dart';

/// App-wide "Recently Watched" state, mirroring [WatchlistProvider]'s
/// pattern for the exact same reason: before this existed, Home's
/// Recently Watched row loaded once in its own State.initState() and
/// never again, so starting/finishing playback (which calls record()/
/// removeItem() on a brand-new RecentlyWatchedService() instance
/// elsewhere - detail_screen.dart, the player screens) never reached
/// that already-built widget. The row only ever caught up on a full app
/// restart, when initState() ran fresh. Routing every read and write
/// through this single shared, listenable instance instead means any
/// screen holding a `context.watch<RecentlyWatchedProvider>()` rebuilds
/// the moment another screen calls record()/removeItem(), the same way
/// bookmarking a title anywhere already updates every watchlist row live.
class RecentlyWatchedProvider extends ChangeNotifier {
  RecentlyWatchedProvider(this._service) {
    _load();
  }

  final RecentlyWatchedService _service;
  List<RecentlyWatchedEntry> _entries = [];
  bool _loaded = false;

  List<RecentlyWatchedEntry> get entries => List.unmodifiable(_entries);
  bool get isLoaded => _loaded;

  Future<void> _load() async {
    _entries = await _service.load();
    _loaded = true;
    notifyListeners();
  }

  /// Re-reads from disk. Exposed for pull-to-refresh; record()/
  /// removeItem() below already re-sync and notify on their own, so this
  /// is only needed to pick up a change made outside the provider's own
  /// calls (there currently isn't one, but it keeps parity with a manual
  /// refresh gesture actually doing something here too).
  Future<void> reload() => _load();

  Future<void> record({required MediaItem item, int? season, int? episode}) async {
    await _service.record(item: item, season: season, episode: episode);
    await _load();
  }

  /// Clears every entry at once, then reloads so any screen watching this
  /// provider empties out immediately (Settings > Data & Storage).
  Future<void> clearAll() async {
    await _service.clearAll();
    await _load();
  }

  Future<void> removeItem(MediaType type, int id, {int? season, int? episode}) async {
    await _service.removeItem(type, id, season: season, episode: episode);
    await _load();
  }
}
