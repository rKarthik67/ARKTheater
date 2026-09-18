import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/languages.dart';
import '../core/responsive.dart';
import '../models/media_item.dart';
import '../models/recently_watched.dart';
import '../services/playback_position_service.dart';
import '../services/tmdb_service.dart';
import '../state/recently_watched_provider.dart';
import '../state/watchlist_provider.dart';
import '../widgets/error_view.dart';
import '../widgets/fade_in_on_scroll.dart';
import '../widgets/hero_banner.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/media_card.dart';
import '../widgets/media_row.dart';
import 'browse_screen.dart';
import 'detail_screen.dart';
import 'movies_screen.dart';
import 'tvshows_screen.dart';
import 'watchlist_screen.dart';

/// Runs [tasks] with at most [concurrency] in flight at once, instead of
/// firing all of them simultaneously like Future.wait does. Home's
/// per-language rows used to blast all 8 languages at TMDB at the same
/// time, twice (movies, then TV) - a burst of simultaneous connections
/// that, combined with this project's api_key being shared across every
/// install of this open-source app, was the likely cause of Home
/// intermittently failing to load some rows. Capping concurrency spreads
/// the same requests out instead of bursting them.
Future<List<T>> _runWithLimitedConcurrency<T>(
  List<Future<T> Function()> tasks, {
  int concurrency = 3,
}) async {
  final results = List<T?>.filled(tasks.length, null);
  var nextIndex = 0;

  Future<void> worker() async {
    while (true) {
      final index = nextIndex++;
      if (index >= tasks.length) return;
      results[index] = await tasks[index]();
    }
  }

  await Future.wait(List.generate(concurrency.clamp(1, tasks.length == 0 ? 1 : tasks.length), (_) => worker()));
  return results.cast<T>();
}

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
  _HomeData? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// Used for both the initial load and pull-to-refresh. Keeps whatever
  /// data is already on screen visible while a refresh is in flight -
  /// pull-to-refresh should never flash the whole screen back to a
  /// spinner, only the first-ever load (when there's nothing to show yet)
  /// does that.
  Future<void> _refresh() async {
    try {
      final data = await _load();
      if (mounted) {
        unawaited(context.read<RecentlyWatchedProvider>().reload());
      }
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
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
    // Run with bounded concurrency rather than Future.wait-ing all 8 of
    // these at once per media type: bursting that many simultaneous
    // requests at TMDB, on this project's shared public demo api_key, is
    // what was making Home intermittently fail to load rows (see
    // _runWithLimitedConcurrency's doc comment).
    final movieLanguageLists = await _runWithLimitedConcurrency([
      for (final (code, _) in kLanguages) () => _tmdb.discoverByLanguage(MediaType.movie, code),
    ]);
    final tvLanguageLists = await _runWithLimitedConcurrency([
      for (final (code, _) in kLanguages) () => _tmdb.discoverByLanguage(MediaType.tv, code),
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
    final data = _data;
    return Scaffold(
      body: Builder(
        builder: (context) {
          if (data == null) {
            return _loading
                ? const LoadingIndicator(label: 'Loading titles...')
                : ErrorView(
                    message: 'Could not load titles.\n$_error',
                    onRetry: _refresh,
                  );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
            // Clears the floating nav bar so the last row isn't stranded
            // underneath it - see Responsive.bottomNavInset.
            padding: EdgeInsets.only(bottom: 24 + Responsive.bottomNavInset(context)),
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
            ),
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
/// Home's Recently Watched rail - reads straight from the app-wide
/// RecentlyWatchedProvider (the same one DetailScreen's record() call and
/// each player screen's removeItem() call write to), the same live-update
/// pattern _WatchlistRow below already uses. Starting or finishing
/// playback anywhere in the app updates this row immediately, with no
/// pull-to-refresh or app restart needed.
class _RecentlyWatchedRow extends StatelessWidget {
  const _RecentlyWatchedRow({required this.onItemTap});

  final void Function(MediaItem) onItemTap;

  // Goes straight into playback instead of the details page - the whole
  // point of "Recently Watched" is one tap to keep watching. DetailScreen
  // does the actual provider-resolving/loading-state work it already has
  // (autoPlay just fires the same _play() its own Play button does), and
  // the player screens themselves seek to the saved position once the
  // stream opens (see PlaybackPositionService).
  void _resume(BuildContext context, RecentlyWatchedEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailScreen(
          item: entry.item,
          onSelectRelated: onItemTap,
          autoPlay: true,
          autoPlaySeason: entry.season,
          autoPlayEpisode: entry.episode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recentlyWatched = context.watch<RecentlyWatchedProvider>();
    if (!recentlyWatched.isLoaded || recentlyWatched.entries.isEmpty) {
      return const SizedBox.shrink();
    }
    final entries = recentlyWatched.entries;
    final columns = Responsive.gridColumns(context);
    final cardWidth =
        (1 / columns * (MediaQuery.sizeOf(context).width - 32) - 8).clamp(110, 220).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeInOnScroll(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Recently Watched', style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: cardWidth * 1.5 + 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return SizedBox(
                  width: cardWidth,
                  child: _RecentlyWatchedCard(entry: entry, onTap: () => _resume(context, entry)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One Recently Watched card. Its resume-progress fraction is looked up
/// per-card (rather than pre-loaded into a map the way the old
/// StatefulWidget version did) so this stays a simple, stateless
/// reader of RecentlyWatchedProvider - PlaybackPositionService's own
/// storage is unaffected by any of this and still keyed the same way.
class _RecentlyWatchedCard extends StatelessWidget {
  const _RecentlyWatchedCard({required this.entry, required this.onTap});

  final RecentlyWatchedEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PlaybackProgress?>(
      future: PlaybackPositionService().loadProgress(
        mediaType: entry.item.type,
        tmdbId: entry.item.id,
        season: entry.season,
        episode: entry.episode,
      ),
      builder: (context, snapshot) {
        return MediaCard(
          item: entry.item,
          onTap: onTap,
          onRemove: () => context.read<RecentlyWatchedProvider>().removeItem(
                entry.item.type,
                entry.item.id,
                season: entry.season,
                episode: entry.episode,
              ),
          subtitle: entry.season != null ? 'S${entry.season} - E${entry.episode}' : null,
          progress: snapshot.data?.fraction,
        );
      },
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
