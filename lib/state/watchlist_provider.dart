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
}
