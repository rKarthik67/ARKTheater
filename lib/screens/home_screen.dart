import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/languages.dart';
import '../models/media_item.dart';
import '../models/recently_watched.dart';
import '../services/recently_watched_service.dart';
import '../services/tmdb_service.dart';
import '../state/watchlist_provider.dart';
import '../widgets/error_view.dart';
import '../widgets/hero_banner.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/media_row.dart';
import 'browse_screen.dart';
import 'movies_screen.dart';
import 'tvshows_screen.dart';
import 'watchlist_screen.dart';

/// How many items a Home row shows before "View more" takes over - Home is
/// meant to be skimmed, not deeply browsed (that's what the Movies/TV Shows
/// tabs and "View more" are for).
const _kRowCap = 15;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onSelect});

  final void Function(MediaItem) onSelect;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _tmdb = TmdbService();
  late Future<_HomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HomeData> _load() async {
    final results = await Future.wait([
      _tmdb.trending(MediaType.movie),
      _tmdb.nowPlaying(),
      _tmdb.topRated(MediaType.movie),
      _tmdb.trending(MediaType.tv),
      _tmdb.topRated(MediaType.tv),
    ]);

    // One row per language, per media type - see core/languages.dart.
    final movieLanguageLists = await Future.wait([
      for (final (code, _) in kLanguages) _tmdb.discoverByLanguage(MediaType.movie, code),
    ]);
    final tvLanguageLists = await Future.wait([
      for (final (code, _) in kLanguages) _tmdb.discoverByLanguage(MediaType.tv, code),
    ]);

    return _HomeData(
      trendingMovies: results[0],
      nowPlaying: results[1],
      topRatedMovies: results[2],
      trendingTv: results[3],
      topRatedTv: results[4],
      movieLanguageRows: {
        for (var i = 0; i < kLanguages.length; i++) kLanguages[i].$1: movieLanguageLists[i],
      },
      tvLanguageRows: {
        for (var i = 0; i < kLanguages.length; i++) kLanguages[i].$1: tvLanguageLists[i],
      },
    );
  }

  void _openMovies({String? language}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MoviesScreen(onSelect: widget.onSelect, initialLanguageCode: language),
      ),
    );
  }

  void _openTv({String? language}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TVShowsScreen(onSelect: widget.onSelect, initialLanguageCode: language),
      ),
    );
  }

  void _openBrowse(
    String title,
    Future<({List<MediaItem> items, int totalPages})> Function(int page) fetchPage,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BrowseScreen(title: title, fetchPage: fetchPage, onSelect: widget.onSelect),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<_HomeData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingIndicator(label: 'Loading titles...');
          }
          if (snapshot.hasError) {
            return ErrorView(
              message: 'Could not load titles.\n${snapshot.error}',
              onRetry: () => setState(() => _future = _load()),
            );
          }
          final data = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              HeroBanner(
                items: data.nowPlaying.take(5).toList(),
                tmdb: _tmdb,
                onWatchNow: widget.onSelect,
              ),
              const SizedBox(height: 8),
              _RecentlyWatchedRow(onItemTap: widget.onSelect),
              _WatchlistRow(
                onItemTap: widget.onSelect,
                onViewMore: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => WatchlistScreen(onSelect: widget.onSelect)),
                ),
              ),
              if (data.trendingMovies.isNotEmpty)
                MediaRow(
                  title: 'Trending Movies',
                  items: data.trendingMovies.take(_kRowCap).toList(),
                  onItemTap: widget.onSelect,
                  onViewMore: () => _openBrowse(
                    'Trending Movies',
                    (page) => _tmdb.trendingPaged(MediaType.movie, page: page),
                  ),
                ),
              if (data.nowPlaying.isNotEmpty)
                MediaRow(
                  title: 'Now Playing',
                  items: data.nowPlaying.take(_kRowCap).toList(),
                  onItemTap: widget.onSelect,
                  onViewMore: () =>
                      _openBrowse('Now Playing', (page) => _tmdb.nowPlayingPaged(page: page)),
                ),
              if (data.topRatedMovies.isNotEmpty)
                MediaRow(
                  title: 'Top Rated Movies',
                  items: data.topRatedMovies.take(_kRowCap).toList(),
                  onItemTap: widget.onSelect,
                  onViewMore: () => _openBrowse(
                    'Top Rated Movies',
                    (page) => _tmdb.topRatedPaged(MediaType.movie, page: page),
                  ),
                ),
              if (data.trendingTv.isNotEmpty)
                MediaRow(
                  title: 'Trending TV Shows',
                  items: data.trendingTv.take(_kRowCap).toList(),
                  onItemTap: widget.onSelect,
                  onViewMore: () => _openBrowse(
                    'Trending TV Shows',
                    (page) => _tmdb.trendingPaged(MediaType.tv, page: page),
                  ),
                ),
              if (data.topRatedTv.isNotEmpty)
                MediaRow(
                  title: 'Top Rated TV Shows',
                  items: data.topRatedTv.take(_kRowCap).toList(),
                  onItemTap: widget.onSelect,
                  onViewMore: () => _openBrowse(
                    'Top Rated TV Shows',
                    (page) => _tmdb.topRatedPaged(MediaType.tv, page: page),
                  ),
                ),
              for (final (code, label) in kLanguages)
                if ((data.movieLanguageRows[code] ?? const []).isNotEmpty)
                  MediaRow(
                    title: '$label Movies',
                    items: (data.movieLanguageRows[code] ?? const []).take(_kRowCap).toList(),
                    onItemTap: widget.onSelect,
                    onViewMore: () => _openMovies(language: code),
                  ),
              for (final (code, label) in kLanguages)
                if ((data.tvLanguageRows[code] ?? const []).isNotEmpty)
                  MediaRow(
                    title: '$label TV Shows',
                    items: (data.tvLanguageRows[code] ?? const []).take(_kRowCap).toList(),
                    onItemTap: widget.onSelect,
                    onViewMore: () => _openTv(language: code),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _HomeData {
  final List<MediaItem> trendingMovies;
  final List<MediaItem> nowPlaying;
  final List<MediaItem> topRatedMovies;
  final List<MediaItem> trendingTv;
  final List<MediaItem> topRatedTv;
  final Map<String, List<MediaItem>> movieLanguageRows;
  final Map<String, List<MediaItem>> tvLanguageRows;

  const _HomeData({
    required this.trendingMovies,
    required this.nowPlaying,
    required this.topRatedMovies,
    required this.trendingTv,
    required this.topRatedTv,
    required this.movieLanguageRows,
    required this.tvLanguageRows,
  });
}

/// Home's own Recently Watched rail - loads/mutates independently of the
/// big _HomeData future above so deleting one entry doesn't require
/// refetching trending/top-rated/language rows too.
class _RecentlyWatchedRow extends StatefulWidget {
  const _RecentlyWatchedRow({required this.onItemTap});

  final void Function(MediaItem) onItemTap;

  @override
  State<_RecentlyWatchedRow> createState() => _RecentlyWatchedRowState();
}

class _RecentlyWatchedRowState extends State<_RecentlyWatchedRow> {
  final _service = RecentlyWatchedService();
  List<RecentlyWatchedEntry> _entries = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await _service.load();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loaded = true;
    });
  }

  Future<void> _remove(MediaItem item) async {
    // Optimistic UI update - removes instantly, persists in the background.
    setState(() {
      _entries = _entries.where((e) => !(e.item.type == item.type && e.item.id == item.id)).toList();
    });
    await _service.removeItem(item.type, item.id);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _entries.isEmpty) return const SizedBox.shrink();
    return MediaRow(
      title: 'Recently Watched',
      items: _entries.map((e) => e.item).toList(),
      onItemTap: widget.onItemTap,
      onItemRemove: _remove,
    );
  }
}

/// Home's own watchlist rail, shown before Trending Movies - reads straight
/// from the app-wide WatchlistProvider (the same one DetailScreen's
/// bookmark button and every MediaCard's overlay bookmark icon write to),
/// so bookmarking a title anywhere shows up here live.
class _WatchlistRow extends StatelessWidget {
  const _WatchlistRow({required this.onItemTap, required this.onViewMore});

  final void Function(MediaItem) onItemTap;
  final VoidCallback onViewMore;

  @override
  Widget build(BuildContext context) {
    final watchlist = context.watch<WatchlistProvider>();
    if (!watchlist.isLoaded || watchlist.items.isEmpty) return const SizedBox.shrink();
    return MediaRow(
      title: 'My Watchlist',
      items: watchlist.items,
      onItemTap: onItemTap,
      onViewMore: onViewMore,
    );
  }
}
