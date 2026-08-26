import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/config.dart';
import '../core/responsive.dart';
import '../core/theme.dart';
import '../models/media_detail.dart';
import '../models/media_item.dart';
import '../services/tmdb_service.dart';
import '../services/recently_watched_service.dart';
import '../state/watchlist_provider.dart';
import '../video_providers/names.dart';
import '../video_providers/provider_loader.dart';
import '../video_providers/scraper_api.dart';
import '../widgets/error_view.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/media_row.dart';
import 'person_detail_screen.dart';
import 'player_screen.dart';
import 'webview_player_screen.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.item, required this.onSelectRelated});

  final MediaItem item;
  final void Function(MediaItem) onSelectRelated;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final _tmdb = TmdbService();
  late Future<MediaDetail> _future;
  int _selectedSeason = 1;
  bool _resolving = false;
  String? _resolvingStatus;

  /// Episodes for the selected season - fetched separately from the main
  /// detail payload (TMDB requires a dedicated /season/{n} call for
  /// episode-level data like stills), so the poster-card episode picker
  /// has something to render.
  List<EpisodeSummary> _episodes = [];
  bool _loadingEpisodes = false;

  /// Loaded once and reused for every play tap: ARKVideoScrapper's live
  /// provider catalog, with the direct VixSrc fallback appended last so
  /// playback still has a chance even if the scraper backend is down.
  List<VideoProvider>? _providers;
  Future<List<VideoProvider>>? _providersFuture;

  @override
  void initState() {
    super.initState();
    _future = _tmdb.details(widget.item.id, widget.item.type);
    _providersFuture = _loadProviders();
    if (widget.item.type == MediaType.tv) {
      _loadEpisodes(_selectedSeason);
    }
  }

  Future<void> _loadEpisodes(int seasonNumber) async {
    setState(() => _loadingEpisodes = true);
    try {
      final episodes = await _tmdb.episodes(widget.item.id, seasonNumber);
      if (!mounted) return;
      setState(() {
        _episodes = episodes;
        _loadingEpisodes = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _episodes = [];
        _loadingEpisodes = false;
      });
    }
  }

  void _onSeasonChanged(int seasonNumber) {
    if (seasonNumber == _selectedSeason) return;
    setState(() => _selectedSeason = seasonNumber);
    _loadEpisodes(seasonNumber);
  }

  Future<List<VideoProvider>> _loadProviders() async {
    try {
      final scraperProviders = await ScraperApi(AppConfig.scraperBaseUrl).getProviders();
      final providers = [...scraperProviders, VideoProvider.directVixSrc];
      _providers = providers;
      return providers;
    } catch (_) {
      // Scraper unreachable (not deployed yet, network hiccup, ...) - fall
      // back to just the direct provider so playback can still work.
      const providers = [VideoProvider.directVixSrc];
      _providers = providers;
      return providers;
    }
  }

  Future<void> _play({int? season, int? episode}) async {
    if (_resolving) return;
    setState(() {
      _resolving = true;
      _resolvingStatus = 'Finding an ad-free source...';
    });

    try {
      final providers = _providers ?? await (_providersFuture ??= _loadProviders());
      if (!mounted) return;

      final selection = await ProviderLoader.loadFirstSuccessful(
        providers: providers,
        load: (provider) => widget.item.type == MediaType.movie
            ? ProviderLoader.loadMovieFromProvider(
                provider: provider,
                movieId: widget.item.id,
                scraperApiUrl: AppConfig.scraperBaseUrl,
              )
            : ProviderLoader.loadTVFromProvider(
                provider: provider,
                tvId: widget.item.id,
                seasonNumber: season!,
                episodeNumber: episode!,
                scraperApiUrl: AppConfig.scraperBaseUrl,
              ),
        onResult: (index, provider, result) {
          if (!mounted) return;
          setState(() => _resolvingStatus = 'Trying ${provider.displayName}...');
        },
      );

      if (!mounted) return;

      if (selection == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No playable source found for this title yet. Try again shortly.'),
            action: SnackBarAction(
              label: 'Watch instead',
              onPressed: () => _openWebViewFallback(season: season, episode: episode),
            ),
          ),
        );
        return;
      }

      await RecentlyWatchedService().record(item: widget.item, season: season, episode: episode);

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            title: widget.item.title + (season != null ? ' - S${season}E$episode' : ''),
            mediaType: widget.item.type,
            tmdbId: widget.item.id,
            season: season,
            episode: episode,
            providers: providers,
            initialProviderIndex: selection.index,
            initialResult: selection.result,
          ),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not resolve a stream: $err')),
      );
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  /// Fallback for when every provider fails: an in-app, ad-blocked WebView
  /// showing a provider's real embed page (see WebViewPlayerScreen), so the
  /// user still has something to watch instead of a dead end.
  void _openWebViewFallback({int? season, int? episode}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebViewPlayerScreen(
          title: widget.item.title,
          type: widget.item.type,
          tmdbId: widget.item.id,
          season: season,
          episode: episode,
        ),
      ),
    );
  }

  void _openPerson(int personId, String personName) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PersonDetailScreen(
          personId: personId,
          personName: personName,
          onSelectTitle: widget.onSelectRelated,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final watchlist = context.watch<WatchlistProvider>();
    final isBookmarked = watchlist.contains(widget.item.type, widget.item.id);

    return Scaffold(
      body: FutureBuilder<MediaDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingIndicator(label: 'Loading details...');
          }
          if (snapshot.hasError) {
            return ErrorView(message: 'Failed to load details.\n${snapshot.error}');
          }
          final detail = snapshot.data!;
          final isTv = widget.item.type == MediaType.tv;
          final isDesktop = Responsive.isDesktop(context);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: isDesktop ? 420 : 260,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (detail.item.backdropUrl() != null)
                        CachedNetworkImage(
                          imageUrl: detail.item.backdropUrl()!,
                          fit: BoxFit.cover,
                        ),
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, AppTheme.background],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  IconButton(
                    icon: Icon(isBookmarked ? Icons.bookmark : Icons.bookmark_border),
                    onPressed: () => watchlist.toggle(detail.item),
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(detail.item.title, style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (detail.item.year.isNotEmpty) _Chip(detail.item.year),
                          if (detail.runtimeMinutes != null)
                            _Chip('${detail.runtimeMinutes}m'),
                          _Chip('★ ${detail.item.voteAverage.toStringAsFixed(1)}'),
                          for (final g in detail.genres.take(3)) _Chip(g),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        detail.item.overview ?? '',
                        style: const TextStyle(color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 20),
                      if (!isTv)
                        ElevatedButton.icon(
                          onPressed: _resolving ? null : () => _play(),
                          icon: _resolving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.play_arrow),
                          label: Text(_resolving ? (_resolvingStatus ?? 'Finding ad-free source...') : 'Play'),
                        )
                      else
                        _SeasonEpisodePicker(
                          seasons: detail.seasons,
                          selectedSeason: _selectedSeason,
                          episodes: _episodes,
                          loadingEpisodes: _loadingEpisodes,
                          resolving: _resolving,
                          resolvingStatus: _resolvingStatus,
                          onSeasonChanged: _onSeasonChanged,
                          onPlayEpisode: (episode) => _play(season: _selectedSeason, episode: episode),
                        ),
                    ],
                  ),
                ),
              ),
              if (detail.cast.isNotEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 150,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: detail.cast.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, i) {
                        final c = detail.cast[i];
                        return SizedBox(
                          width: 90,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _openPerson(c.id, c.name),
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 36,
                                  backgroundColor: AppTheme.surfaceVariant,
                                  backgroundImage: c.profilePath != null
                                      ? CachedNetworkImageProvider(
                                          'https://image.tmdb.org/t/p/w200${c.profilePath}')
                                      : null,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  c.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: MediaRow(
                  title: 'Similar Titles',
                  items: detail.similar,
                  onItemTap: widget.onSelectRelated,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _SeasonEpisodePicker extends StatelessWidget {
  const _SeasonEpisodePicker({
    required this.seasons,
    required this.selectedSeason,
    required this.episodes,
    required this.loadingEpisodes,
    required this.resolving,
    required this.resolvingStatus,
    required this.onSeasonChanged,
    required this.onPlayEpisode,
  });

  final List<SeasonSummary> seasons;
  final int selectedSeason;
  final List<EpisodeSummary> episodes;
  final bool loadingEpisodes;
  final bool resolving;
  final String? resolvingStatus;
  final ValueChanged<int> onSeasonChanged;
  final ValueChanged<int> onPlayEpisode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Seasons', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        SizedBox(
          // Poster (2:3 at width 100 -> 150 tall) + label gap + a text
          // line needs ~184px total; 150 was clipping the label and
          // spilling an overflow banner into the Episodes section below.
          height: 184,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: seasons.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final s = seasons[i];
              final selected = s.seasonNumber == selectedSeason;
              return _SeasonCard(
                season: s,
                selected: selected,
                onTap: () => onSeasonChanged(s.seasonNumber),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        const Text('Episodes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        if (resolving && resolvingStatus != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
                ),
                const SizedBox(width: 8),
                Text(resolvingStatus!, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        if (loadingEpisodes)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
          )
        else
          Column(
            children: [
              for (var i = 0; i < episodes.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _EpisodeRow(
                  episode: episodes[i],
                  enabled: !resolving,
                  onTap: () => onPlayEpisode(episodes[i].episodeNumber),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

class _SeasonCard extends StatelessWidget {
  const _SeasonCard({required this.season, required this.selected, required this.onTap});

  final SeasonSummary season;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final posterUrl = season.posterUrl();
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: SizedBox(
        width: 100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? AppTheme.accent : Colors.transparent,
                    width: 2,
                  ),
                  color: AppTheme.surfaceVariant,
                ),
                child: posterUrl != null
                    ? CachedNetworkImage(imageUrl: posterUrl, fit: BoxFit.cover)
                    : const Icon(Icons.tv, color: AppTheme.textSecondary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              season.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: selected ? AppTheme.accent : AppTheme.textPrimary,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width episode row (thumbnail + title + summary) instead of a
/// horizontally-scrolling card, so the synopsis actually has room to show.
class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.episode, required this.enabled, required this.onTap});

  final EpisodeSummary episode;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stillUrl = episode.stillUrl();
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: AppTheme.surfaceVariant,
                        ),
                        child: stillUrl != null
                            ? CachedNetworkImage(imageUrl: stillUrl, fit: BoxFit.cover)
                            : const Icon(Icons.image_not_supported_outlined, color: AppTheme.textSecondary),
                      ),
                    ),
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('E${episode.episodeNumber}', style: const TextStyle(fontSize: 11, color: Colors.white)),
                      ),
                    ),
                    const Positioned.fill(
                      child: Center(
                        child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 30),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    episode.name.isNotEmpty
                        ? 'E${episode.episodeNumber} · ${episode.name}'
                        : 'Episode ${episode.episodeNumber}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  if ((episode.overview ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      episode.overview!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.3),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
