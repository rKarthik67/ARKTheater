import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/responsive.dart';
import '../core/theme.dart';
import '../models/media_item.dart';
import '../state/watchlist_provider.dart';
import '../widgets/fade_in_on_scroll.dart';
import '../widgets/media_card.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key, required this.onSelect});

  final void Function(MediaItem) onSelect;

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  static const _sortPreferenceKey = 'ark_theater.watchlist.sort.v1';
  MediaType _mediaType = MediaType.movie;
  WatchlistSort _sort = WatchlistSort.watchedNewest;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadSortPreference();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final watchlist = context.watch<WatchlistProvider>();
    final items = watchlist.items;
    final movies = items.where((i) => i.type == MediaType.movie).toList();
    final tvShows = items.where((i) => i.type == MediaType.tv).toList();
    final selected = _mediaType == MediaType.movie ? movies : tvShows;
    final query = _query.trim().toLowerCase();
    final shown = query.isEmpty
        ? selected
        : selected.where((item) {
            return item.title.toLowerCase().contains(query) ||
                item.year.contains(query);
          }).toList();
    _sortItems(shown);

    return Scaffold(
      appBar: AppBar(title: const Text('My Watchlist')),
      body: !watchlist.isLoaded
          ? const SizedBox.shrink()
          : items.isEmpty
              ? Center(
                  child: Text(
                    'Titles you bookmark show up here.',
                    style: TextStyle(color: AppTheme.textSecondaryOf(context)),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: SegmentedButton<MediaType>(
                        segments: [
                          ButtonSegment(
                            value: MediaType.movie,
                            label: Text('Movies (${movies.length})'),
                            icon: const Icon(Icons.movie_outlined),
                          ),
                          ButtonSegment(
                            value: MediaType.tv,
                            label: Text('TV Shows (${tvShows.length})'),
                            icon: const Icon(Icons.tv_outlined),
                          ),
                        ],
                        selected: {_mediaType},
                        onSelectionChanged: (selection) => setState(() => _mediaType = selection.first),
                        style: ButtonStyle(
                          foregroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected) ? Colors.white : AppTheme.textSecondaryOf(context),
                          ),
                          backgroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected) ? AppTheme.accent : AppTheme.surfaceVariantOf(context),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: DropdownButtonFormField<WatchlistSort>(
                        value: _sort,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Sort by',
                          prefixIcon: const Icon(Icons.sort),
                          filled: true,
                          fillColor: AppTheme.surfaceVariantOf(context),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: AppTheme.borderOf(context)),
                          ),
                        ),
                        dropdownColor: AppTheme.surfaceVariantOf(context),
                        items: WatchlistSort.values
                            .map(
                              (sort) => DropdownMenuItem(
                                value: sort,
                                child: Text(sort.label),
                              ),
                            )
                            .toList(),
                        onChanged: (sort) {
                          if (sort != null) _setSort(sort);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _query = value),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search your watchlist',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _query = '');
                                  },
                                ),
                          filled: true,
                          fillColor: AppTheme.surfaceVariantOf(context),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: AppTheme.borderOf(context)),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: shown.isEmpty
                          ? Center(
                              child: Text(
                                query.isNotEmpty
                                    ? 'No matching titles in your watchlist.'
                                    : _mediaType == MediaType.movie
                                    ? 'No movies in your watchlist yet.'
                                    : 'No TV shows in your watchlist yet.',
                                style: TextStyle(color: AppTheme.textSecondaryOf(context)),
                              ),
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: Responsive.gridColumns(context),
                                childAspectRatio: 0.56,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 16,
                              ),
                              itemCount: shown.length,
                              itemBuilder: (context, index) {
                                final item = shown[index];
                                return FadeInOnScroll(
                                  colorSweep: false,
                                  delay: Duration(milliseconds: 30 * (index % 8)),
                                  child: MediaCard(item: item, onTap: () => widget.onSelect(item)),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Future<void> _loadSortPreference() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_sortPreferenceKey);
    // Migrate the former default so existing users immediately see the title
    // they just played at the front. Other explicit sort choices are kept.
    if (saved == null || saved == WatchlistSort.addedNewest.name) {
      if (mounted) setState(() => _sort = WatchlistSort.watchedNewest);
      await preferences.setString(_sortPreferenceKey, WatchlistSort.watchedNewest.name);
      return;
    }
    final sort = WatchlistSort.values.where((value) => value.name == saved);
    if (mounted && sort.isNotEmpty) {
      setState(() => _sort = sort.first);
    }
  }

  Future<void> _setSort(WatchlistSort sort) async {
    setState(() => _sort = sort);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_sortPreferenceKey, sort.name);
  }

  void _sortItems(List<MediaItem> items) {
    final indexed = items.indexed.toList();
    indexed.sort((a, b) {
      final first = a.$2;
      final second = b.$2;
      final comparison = switch (_sort) {
        WatchlistSort.watchedNewest =>
          (second.watchlistLastWatchedAt?.millisecondsSinceEpoch ??
              second.watchlistAddedAt?.millisecondsSinceEpoch ?? 0)
              .compareTo(first.watchlistLastWatchedAt?.millisecondsSinceEpoch ??
                  first.watchlistAddedAt?.millisecondsSinceEpoch ?? 0),
        WatchlistSort.addedNewest =>
          (second.watchlistAddedAt?.millisecondsSinceEpoch ?? 0)
              .compareTo(first.watchlistAddedAt?.millisecondsSinceEpoch ?? 0),
        WatchlistSort.addedOldest =>
          (first.watchlistAddedAt?.millisecondsSinceEpoch ?? 0)
              .compareTo(second.watchlistAddedAt?.millisecondsSinceEpoch ?? 0),
        WatchlistSort.titleAscending =>
          first.title.toLowerCase().compareTo(second.title.toLowerCase()),
        WatchlistSort.ratingHighest =>
          second.voteAverage.compareTo(first.voteAverage),
      };
      return comparison != 0
          ? comparison
          : _compareStableItems(first, second);
    });
    items
      ..clear()
      ..addAll(indexed.map((entry) => entry.$2));
  }

  int _compareStableItems(MediaItem first, MediaItem second) =>
      first.type.index.compareTo(second.type.index) != 0
          ? first.type.index.compareTo(second.type.index)
          : first.id.compareTo(second.id);
}

enum WatchlistSort {
  watchedNewest('Recently watched — newest first'),
  addedNewest('Date added — newest first'),
  addedOldest('Date added — oldest first'),
  titleAscending('Title — A to Z'),
  ratingHighest('Rating — highest first');

  const WatchlistSort(this.label);
  final String label;
}
