import 'dart:async';
import 'package:flutter/material.dart';
import '../core/languages.dart';
import '../core/responsive.dart';
import '../core/theme.dart';
import '../models/genre.dart';
import '../models/media_item.dart';
import '../models/person_detail.dart';
import '../services/recent_searches_service.dart';
import '../services/tmdb_service.dart';
import '../widgets/error_view.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/paged_media_grid.dart';
import '../widgets/media_card.dart';
import 'person_detail_screen.dart';

/// TV-only filter: how many seasons a show has. TMDB's /search and
/// /discover endpoints don't expose this directly, so it's applied
/// client-side by fetching `number_of_seasons` for whatever's on screen
/// (see _TVResultsState._applySeasonFilter).
enum _SeasonCountFilter { any, one, twoToFour, fivePlus }

extension on _SeasonCountFilter {
  String get label => switch (this) {
        _SeasonCountFilter.any => 'Any Seasons',
        _SeasonCountFilter.one => '1 Season',
        _SeasonCountFilter.twoToFour => '2-4 Seasons',
        _SeasonCountFilter.fivePlus => '5+ Seasons',
      };

  bool matches(int? count) {
    switch (this) {
      case _SeasonCountFilter.any:
        return true;
      case _SeasonCountFilter.one:
        return count == 1;
      case _SeasonCountFilter.twoToFour:
        return count != null && count >= 2 && count <= 4;
      case _SeasonCountFilter.fivePlus:
        return count != null && count >= 5;
    }
  }
}

/// Search, tabbed Movies / TV Shows / People - mirrors flixquest's own
/// search pattern (three tabs, recent-searches list when the field is
/// empty) plus this app's own request: genre + language + year filters on
/// the Movies/TV tabs, and a season-count filter on the TV tab.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.onSelect});

  final void Function(MediaItem) onSelect;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with SingleTickerProviderStateMixin {
  final _tmdb = TmdbService();
  final _recentSearches = RecentSearchesService();
  final _controller = TextEditingController();
  late final TabController _tabController;
  Timer? _debounce;
  String _query = '';

  int? _movieGenreId;
  String? _movieLanguage;
  int? _movieYear;

  int? _tvGenreId;
  String? _tvLanguage;
  int? _tvYear;
  _SeasonCountFilter _seasonFilter = _SeasonCountFilter.any;

  late final Future<List<Genre>> _movieGenresFuture;
  late final Future<List<Genre>> _tvGenresFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _movieGenresFuture = _tmdb.genres(MediaType.movie);
    _tvGenresFuture = _tmdb.genres(MediaType.tv);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _query = value.trim());
      if (_query.isNotEmpty) _recentSearches.add(_query);
    });
  }

  void _onSubmitted(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    setState(() => _query = trimmed);
    if (trimmed.isNotEmpty) _recentSearches.add(trimmed);
  }

  void _searchAgain(String term) {
    _debounce?.cancel();
    _controller.text = term;
    _controller.selection = TextSelection.collapsed(offset: term.length);
    setState(() => _query = term);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: _onSubmitted,
          decoration: const InputDecoration(
            hintText: 'Search movies & TV shows...',
            border: InputBorder.none,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              _debounce?.cancel();
              _controller.clear();
              setState(() => _query = '');
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Movies'), Tab(text: 'TV Shows'), Tab(text: 'People')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _MovieResults(
            tmdb: _tmdb,
            query: _query,
            genresFuture: _movieGenresFuture,
            genreId: _movieGenreId,
            language: _movieLanguage,
            year: _movieYear,
            onGenreChanged: (v) => setState(() => _movieGenreId = v),
            onLanguageChanged: (v) => setState(() => _movieLanguage = v),
            onYearChanged: (v) => setState(() => _movieYear = v),
            onSelect: widget.onSelect,
            recentSearches: _recentSearches,
            onSearchAgain: _searchAgain,
          ),
          _TVResults(
            tmdb: _tmdb,
            query: _query,
            genresFuture: _tvGenresFuture,
            genreId: _tvGenreId,
            language: _tvLanguage,
            year: _tvYear,
            seasonFilter: _seasonFilter,
            onGenreChanged: (v) => setState(() => _tvGenreId = v),
            onLanguageChanged: (v) => setState(() => _tvLanguage = v),
            onYearChanged: (v) => setState(() => _tvYear = v),
            onSeasonFilterChanged: (v) => setState(() => _seasonFilter = v),
            onSelect: widget.onSelect,
            recentSearches: _recentSearches,
            onSearchAgain: _searchAgain,
          ),
          _PeopleResults(
            tmdb: _tmdb,
            query: _query,
            onSelect: widget.onSelect,
            recentSearches: _recentSearches,
            onSearchAgain: _searchAgain,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Shared bits: recent-searches view, genre/language/year filter bar
// ─────────────────────────────────────────────────────────────────────────

class _RecentSearchesView extends StatefulWidget {
  const _RecentSearchesView({required this.service, required this.onSearchAgain});

  final RecentSearchesService service;
  final void Function(String) onSearchAgain;

  @override
  State<_RecentSearchesView> createState() => _RecentSearchesViewState();
}

class _RecentSearchesViewState extends State<_RecentSearchesView> {
  late Future<List<String>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.service.load();
  }

  void _refresh() => setState(() => _future = widget.service.load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: _future,
      builder: (context, snapshot) {
        final terms = snapshot.data ?? const [];
        if (terms.isEmpty) {
          return const Center(
            child: Text('Start typing to search', style: TextStyle(color: AppTheme.textSecondary)),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Recent Searches', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: () async {
                      await widget.service.clear();
                      _refresh();
                    },
                    child: const Text('Clear all'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: terms.length,
                itemBuilder: (context, index) => ListTile(
                  leading: const Icon(Icons.history, color: AppTheme.textSecondary),
                  title: Text(terms[index]),
                  onTap: () => widget.onSearchAgain(terms[index]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}


/// Compact horizontal recent-searches strip shown above the default
/// browse grid on the Movies/TV tabs - keeps recent-search history around
/// even though the default empty-query view is now a browsable grid
/// rather than a full-screen recent-searches list.
class _RecentSearchesRow extends StatefulWidget {
  const _RecentSearchesRow({required this.service, required this.onSearchAgain});

  final RecentSearchesService service;
  final void Function(String) onSearchAgain;

  @override
  State<_RecentSearchesRow> createState() => _RecentSearchesRowState();
}

class _RecentSearchesRowState extends State<_RecentSearchesRow> {
  late Future<List<String>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.service.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: _future,
      builder: (context, snapshot) {
        final terms = snapshot.data ?? const [];
        if (terms.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            children: [
              for (final term in terms) ...[
                ActionChip(
                  avatar: const Icon(Icons.history, size: 16, color: AppTheme.textSecondary),
                  label: Text(term, style: const TextStyle(fontSize: 12)),
                  backgroundColor: AppTheme.surfaceVariant,
                  side: BorderSide.none,
                  onPressed: () => widget.onSearchAgain(term),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _DropdownChip<T> extends StatelessWidget {
  const _DropdownChip({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          dropdownColor: AppTheme.surfaceVariant,
          icon: const Icon(Icons.expand_more, size: 18, color: AppTheme.textSecondary),
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
          items: items,
          // DropdownButton<T>.onChanged is `void Function(T?)?` - T is
          // already nullable everywhere this is used (int?/String?), but
          // Dart doesn't collapse `T?` to `T` for an unbound generic
          // parameter the way it does for a concrete type, so this needs
          // an explicit (safe - T itself accepts null) cast through.
          onChanged: (v) => onChanged(v as T),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.genres,
    required this.genreId,
    required this.language,
    required this.year,
    required this.onGenreChanged,
    required this.onLanguageChanged,
    required this.onYearChanged,
  });

  final List<Genre> genres;
  final int? genreId;
  final String? language;
  final int? year;
  final ValueChanged<int?> onGenreChanged;
  final ValueChanged<String?> onLanguageChanged;
  final ValueChanged<int?> onYearChanged;

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          _DropdownChip<int?>(
            value: genreId,
            items: [
              const DropdownMenuItem(value: null, child: Text('All Genres')),
              for (final g in genres) DropdownMenuItem(value: g.id, child: Text(g.name)),
            ],
            onChanged: onGenreChanged,
          ),
          const SizedBox(width: 8),
          _DropdownChip<String?>(
            value: language,
            items: [
              const DropdownMenuItem(value: null, child: Text('All Languages')),
              for (final (code, label) in kLanguages) DropdownMenuItem(value: code, child: Text(label)),
            ],
            onChanged: onLanguageChanged,
          ),
          const SizedBox(width: 8),
          _DropdownChip<int?>(
            value: year,
            items: [
              const DropdownMenuItem(value: null, child: Text('All Years')),
              for (var y = currentYear; y >= 1950; y--) DropdownMenuItem(value: y, child: Text('$y')),
            ],
            onChanged: onYearChanged,
          ),
        ],
      ),
    );
  }
}

Widget _resultsGrid(BuildContext context, List<MediaItem> results, void Function(MediaItem) onSelect) {
  if (results.isEmpty) {
    return const Center(child: Text('No results', style: TextStyle(color: AppTheme.textSecondary)));
  }
  final columns = Responsive.gridColumns(context);
  return GridView.builder(
    padding: const EdgeInsets.all(16),
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      childAspectRatio: 0.56,
      crossAxisSpacing: 12,
      mainAxisSpacing: 16,
    ),
    itemCount: results.length,
    itemBuilder: (context, index) {
      final item = results[index];
      return MediaCard(item: item, onTap: () => onSelect(item));
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────
// Movies tab
// ─────────────────────────────────────────────────────────────────────────

class _MovieResults extends StatefulWidget {
  const _MovieResults({
    required this.tmdb,
    required this.query,
    required this.genresFuture,
    required this.genreId,
    required this.language,
    required this.year,
    required this.onGenreChanged,
    required this.onLanguageChanged,
    required this.onYearChanged,
    required this.onSelect,
    required this.recentSearches,
    required this.onSearchAgain,
  });

  final TmdbService tmdb;
  final String query;
  final Future<List<Genre>> genresFuture;
  final int? genreId;
  final String? language;
  final int? year;
  final ValueChanged<int?> onGenreChanged;
  final ValueChanged<String?> onLanguageChanged;
  final ValueChanged<int?> onYearChanged;
  final void Function(MediaItem) onSelect;
  final RecentSearchesService recentSearches;
  final void Function(String) onSearchAgain;

  @override
  State<_MovieResults> createState() => _MovieResultsState();
}

class _MovieResultsState extends State<_MovieResults> {
  Future<List<MediaItem>>? _future;
  String? _lastQuery;

  @override
  void initState() {
    super.initState();
    _lastQuery = widget.query;
    _future = widget.query.isEmpty ? null : widget.tmdb.searchMovies(widget.query);
  }

  @override
  void didUpdateWidget(covariant _MovieResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _lastQuery) {
      _lastQuery = widget.query;
      _future = widget.query.isEmpty ? null : widget.tmdb.searchMovies(widget.query);
    }
  }

  // NOTE: genre/language/year narrow whatever page of search results TMDB
  // already returned, client-side - TMDB's /search endpoints don't accept
  // discover-style filter params. For server-side filtered browsing across
  // every page, use the Movies tab instead (no search query needed there).
  List<MediaItem> _applyFilters(List<MediaItem> items) {
    return items.where((item) {
      if (widget.genreId != null && !item.genreIds.contains(widget.genreId)) return false;
      if (widget.language != null && item.originalLanguage != widget.language) return false;
      if (widget.year != null && item.year != '${widget.year}') return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FutureBuilder<List<Genre>>(
          future: widget.genresFuture,
          builder: (context, snapshot) => _FilterBar(
            genres: snapshot.data ?? const [],
            genreId: widget.genreId,
            language: widget.language,
            year: widget.year,
            onGenreChanged: widget.onGenreChanged,
            onLanguageChanged: widget.onLanguageChanged,
            onYearChanged: widget.onYearChanged,
          ),
        ),
        Expanded(
          child: widget.query.isEmpty
              ? Column(
                  children: [
                    _RecentSearchesRow(
                      service: widget.recentSearches,
                      onSearchAgain: widget.onSearchAgain,
                    ),
                    Expanded(
                      // No query yet - show a filterable browse grid (same
                      // genre/language/year filters as search results) instead
                      // of an empty screen, so the tab is never a dead end.
                      child: PagedMediaGrid(
                        key: ValueKey('movie-browse-${widget.genreId}-${widget.language}-${widget.year}'),
                        fetchPage: (page) => widget.tmdb.discover(
                          MediaType.movie,
                          genreId: widget.genreId,
                          languageCode: widget.language,
                          year: widget.year,
                          page: page,
                        ),
                        onSelect: widget.onSelect,
                      ),
                    ),
                  ],
                )
              : FutureBuilder<List<MediaItem>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) return const LoadingIndicator();
                    if (snapshot.hasError) return ErrorView(message: 'Search failed.\n${snapshot.error}');
                    final results = _applyFilters(snapshot.data ?? const []);
                    return _resultsGrid(context, results, widget.onSelect);
                  },
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// TV Shows tab
// ─────────────────────────────────────────────────────────────────────────

class _TVResults extends StatefulWidget {
  const _TVResults({
    required this.tmdb,
    required this.query,
    required this.genresFuture,
    required this.genreId,
    required this.language,
    required this.year,
    required this.seasonFilter,
    required this.onGenreChanged,
    required this.onLanguageChanged,
    required this.onYearChanged,
    required this.onSeasonFilterChanged,
    required this.onSelect,
    required this.recentSearches,
    required this.onSearchAgain,
  });

  final TmdbService tmdb;
  final String query;
  final Future<List<Genre>> genresFuture;
  final int? genreId;
  final String? language;
  final int? year;
  final _SeasonCountFilter seasonFilter;
  final ValueChanged<int?> onGenreChanged;
  final ValueChanged<String?> onLanguageChanged;
  final ValueChanged<int?> onYearChanged;
  final ValueChanged<_SeasonCountFilter> onSeasonFilterChanged;
  final void Function(MediaItem) onSelect;
  final RecentSearchesService recentSearches;
  final void Function(String) onSearchAgain;

  @override
  State<_TVResults> createState() => _TVResultsState();
}

class _TVResultsState extends State<_TVResults> {
  Future<List<MediaItem>>? _future;
  String? _lastQuery;
  final Map<int, int?> _seasonCountCache = {};

  @override
  void initState() {
    super.initState();
    _lastQuery = widget.query;
    _future = widget.query.isEmpty ? null : widget.tmdb.searchTV(widget.query);
  }

  @override
  void didUpdateWidget(covariant _TVResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _lastQuery) {
      _lastQuery = widget.query;
      _future = widget.query.isEmpty ? null : widget.tmdb.searchTV(widget.query);
    }
  }

  List<MediaItem> _applyBaseFilters(List<MediaItem> items) {
    return items.where((item) {
      if (widget.genreId != null && !item.genreIds.contains(widget.genreId)) return false;
      if (widget.language != null && item.originalLanguage != widget.language) return false;
      if (widget.year != null && item.year != '${widget.year}') return false;
      return true;
    }).toList();
  }

  // Season counts aren't in the search response, so this fetches them (with
  // a per-screen cache) only for whichever titles survived the filters
  // above, and only when a season-count filter is actually active.
  Future<List<MediaItem>> _applySeasonFilter(List<MediaItem> items) async {
    if (widget.seasonFilter == _SeasonCountFilter.any) return items;
    final counts = await Future.wait(items.map((item) async {
      if (!_seasonCountCache.containsKey(item.id)) {
        _seasonCountCache[item.id] = await widget.tmdb.tvSeasonCount(item.id);
      }
      return _seasonCountCache[item.id];
    }));
    final filtered = <MediaItem>[];
    for (var i = 0; i < items.length; i++) {
      if (widget.seasonFilter.matches(counts[i])) filtered.add(items[i]);
    }
    return filtered;
  }

  // Powers the empty-query browse grid below - same genre/language/year
  // filters as search results, plus the season-count filter applied
  // per-page (see _applySeasonFilter) so it behaves consistently whether
  // or not a query has been typed yet.
  Future<({List<MediaItem> items, int totalPages})> _tvBrowseFetchPage(int page) async {
    final result = await widget.tmdb.discover(
      MediaType.tv,
      genreId: widget.genreId,
      languageCode: widget.language,
      year: widget.year,
      page: page,
    );
    if (widget.seasonFilter == _SeasonCountFilter.any) return result;
    final filtered = await _applySeasonFilter(result.items);
    return (items: filtered, totalPages: result.totalPages);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FutureBuilder<List<Genre>>(
          future: widget.genresFuture,
          builder: (context, snapshot) => _FilterBar(
            genres: snapshot.data ?? const [],
            genreId: widget.genreId,
            language: widget.language,
            year: widget.year,
            onGenreChanged: widget.onGenreChanged,
            onLanguageChanged: widget.onLanguageChanged,
            onYearChanged: widget.onYearChanged,
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final f in _SeasonCountFilter.values) ...[
                ChoiceChip(
                  label: Text(f.label),
                  selected: f == widget.seasonFilter,
                  onSelected: (_) => widget.onSeasonFilterChanged(f),
                  showCheckmark: false,
                  selectedColor: AppTheme.accent,
                  backgroundColor: AppTheme.surfaceVariant,
                  labelStyle: TextStyle(
                    color: f == widget.seasonFilter ? Colors.white : AppTheme.textPrimary,
                    fontSize: 11,
                  ),
                  side: BorderSide.none,
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        Expanded(
          child: widget.query.isEmpty
              ? Column(
                  children: [
                    _RecentSearchesRow(
                      service: widget.recentSearches,
                      onSearchAgain: widget.onSearchAgain,
                    ),
                    Expanded(
                      child: PagedMediaGrid(
                        key: ValueKey(
                          'tv-browse-${widget.genreId}-${widget.language}-${widget.year}-${widget.seasonFilter}',
                        ),
                        fetchPage: _tvBrowseFetchPage,
                        onSelect: widget.onSelect,
                      ),
                    ),
                  ],
                )
              : FutureBuilder<List<MediaItem>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) return const LoadingIndicator();
                    if (snapshot.hasError) return ErrorView(message: 'Search failed.\n${snapshot.error}');
                    final base = _applyBaseFilters(snapshot.data ?? const []);
                    return FutureBuilder<List<MediaItem>>(
                      future: _applySeasonFilter(base),
                      builder: (context, seasonSnapshot) {
                        if (!seasonSnapshot.hasData) return const LoadingIndicator();
                        return _resultsGrid(context, seasonSnapshot.data!, widget.onSelect);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// People tab
// ─────────────────────────────────────────────────────────────────────────

class _PeopleResults extends StatefulWidget {
  const _PeopleResults({
    required this.tmdb,
    required this.query,
    required this.onSelect,
    required this.recentSearches,
    required this.onSearchAgain,
  });

  final TmdbService tmdb;
  final String query;
  final void Function(MediaItem) onSelect;
  final RecentSearchesService recentSearches;
  final void Function(String) onSearchAgain;

  @override
  State<_PeopleResults> createState() => _PeopleResultsState();
}

class _PeopleResultsState extends State<_PeopleResults> {
  Future<List<PersonSummary>>? _future;
  String? _lastQuery;

  @override
  void initState() {
    super.initState();
    _lastQuery = widget.query;
    _future = widget.query.isEmpty ? null : widget.tmdb.searchPeople(widget.query);
  }

  @override
  void didUpdateWidget(covariant _PeopleResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _lastQuery) {
      _lastQuery = widget.query;
      _future = widget.query.isEmpty ? null : widget.tmdb.searchPeople(widget.query);
    }
  }

  void _openPerson(PersonSummary person) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PersonDetailScreen(
          personId: person.id,
          personName: person.name,
          onSelectTitle: widget.onSelect,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.query.isEmpty) {
      return _RecentSearchesView(service: widget.recentSearches, onSearchAgain: widget.onSearchAgain);
    }
    return FutureBuilder<List<PersonSummary>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const LoadingIndicator();
        if (snapshot.hasError) return ErrorView(message: 'Search failed.\n${snapshot.error}');
        final people = snapshot.data ?? const [];
        if (people.isEmpty) {
          return const Center(child: Text('No results', style: TextStyle(color: AppTheme.textSecondary)));
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: people.length,
          itemBuilder: (context, index) {
            final person = people[index];
            final photo = person.profileUrl();
            return ListTile(
              leading: CircleAvatar(
                radius: 24,
                backgroundColor: AppTheme.surfaceVariant,
                backgroundImage: photo != null ? NetworkImage(photo) : null,
                child: photo == null
                    ? const Icon(Icons.person_outline, color: AppTheme.textSecondary)
                    : null,
              ),
              title: Text(person.name),
              onTap: () => _openPerson(person),
            );
          },
        );
      },
    );
  }
}
