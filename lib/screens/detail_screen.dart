import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/config.dart';
import '../core/responsive.dart';
import '../core/app_fonts.dart';
import '../core/theme.dart';
import '../models/media_detail.dart';
import '../models/media_item.dart';
import '../services/tmdb_service.dart';
import '../state/recently_watched_provider.dart';
import '../state/watchlist_provider.dart';
import '../video_providers/names.dart';
import '../video_providers/common.dart';
import '../video_providers/provider_loader.dart';
import '../video_providers/scraper_api.dart';
import '../core/embed_providers.dart';
import '../widgets/error_view.dart';
import '../widgets/fade_in_on_scroll.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/media_row.dart';
import 'person_detail_screen.dart';
import 'player_screen.dart';
import 'webview_player_screen.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.item,
    required this.onSelectRelated,
    this.autoPlay = false,
    this.autoPlaySeason,
    this.autoPlayEpisode,
  });

  final MediaItem item;
  final void Function(MediaItem) onSelectRelated;

  /// Set when this screen was opened from "Recently Watched" to resume
  /// playback immediately instead of requiring another tap on Play -
  /// PlaybackPositionService (inside the player screens) does the actual
  /// seek-to-last-position once playback opens. autoPlaySeason/Episode are
  /// null for a movie and set for a specific TV episode.
  final bool autoPlay;
  final int? autoPlaySeason;
  final int? autoPlayEpisode;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _StreamChoice {
  const _StreamChoice.scraper(this.index) : isEmbed = false;
  const _StreamChoice.embed(this.index) : isEmbed = true;

  final int index;
  final bool isEmbed;
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
  /// provider catalog. Web embeds deliberately live in their own chooser
  /// tab, rather than being silently used as a scraper-stream fallback.
  List<VideoProvider>? _providers;
  Future<List<VideoProvider>>? _providersFuture;

  @override
  void initState() {
    super.initState();
    _future = _tmdb.details(widget.item.id, widget.item.type);
    _providersFuture = _loadProviders();
    if (widget.item.type == MediaType.tv) {
      if (widget.autoPlay && widget.autoPlaySeason != null) {
        _selectedSeason = widget.autoPlaySeason!;
      }
      _loadEpisodes(_selectedSeason);
    }
    if (widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _play(
            season: widget.autoPlaySeason,
            episode: widget.autoPlayEpisode,
            chooseProvider: false,
          );
        }
      });
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
      final providers = await ScraperApi(AppConfig.scraperBaseUrl).getProviders();
      _providers = providers;
      return providers;
    } catch (_) {
      // The embed tab remains available even if the scraper is unavailable.
      const providers = <VideoProvider>[];
      _providers = providers;
      return providers;
    }
  }

  /// Reads the scraper's latest scheduled health snapshot immediately before
  /// Auto starts resolving a title. Health is advisory (a provider can be
  /// online generally but lack this particular title), so offline providers
  /// remain as a last fallback; actual title-level loading still decides the
  /// final playable source.
  Future<List<VideoProvider>> _providersForAuto(
    List<VideoProvider> providers,
  ) async {
    try {
      final health = await ScraperApi(AppConfig.scraperBaseUrl)
          .getProviderHealthStatus();
      final statusById = {
        for (final provider in health.providers) provider.id: provider,
      };
      final online = <VideoProvider>[];
      final unknown = <VideoProvider>[];
      final offline = <VideoProvider>[];
      for (final provider in providers) {
        final state = statusById[provider.apiId ?? ''];
        if (state?.isOnline == true) {
          online.add(provider);
        } else if (state?.isOffline == true) {
          offline.add(provider);
        } else {
          unknown.add(provider);
        }
      }
      // Do not let an old all-offline snapshot make Auto give up. The
      // following actual stream loads are the final, title-specific test.
      return online.isEmpty ? providers : [...online, ...unknown, ...offline];
    } catch (_) {
      // Status is helpful but never blocks playback if the status endpoint
      // itself is temporarily unavailable.
      return providers;
    }
  }

  Future<void> _play({
    int? season,
    int? episode,
    bool chooseProvider = true,
  }) async {
    if (_resolving) return;

    final providers = _providers ?? await (_providersFuture ??= _loadProviders());
    if (!mounted) return;

    final choice = chooseProvider
        ? await _showProviderPicker(providers)
        : const _StreamChoice.scraper(-1);
    if (choice == null || !mounted) return;

    if (choice.isEmbed) {
      _openWebViewEmbed(choice.index, season: season, episode: episode);
      return;
    }
    final selectedIndex = choice.index;

    setState(() {
      _resolving = true;
      _resolvingStatus = 'Finding an ad-free source...';
    });

    try {
      Future<ProviderLoadResult> load(VideoProvider provider) {
        return widget.item.type == MediaType.movie
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
              );
      }

      final ProviderSelection? selection;
      if (selectedIndex == -1) {
        setState(() => _resolvingStatus = 'Checking provider status...');
        final autoProviders = await _providersForAuto(providers);
        if (!mounted) return;
        selection = await ProviderLoader.loadFirstSuccessful(
          providers: autoProviders,
          load: load,
          onResult: (index, provider, result) {
            if (!mounted) return;
            setState(() => _resolvingStatus = 'Trying ${provider.displayName}...');
          },
        );
      } else {
        final provider = providers[selectedIndex];
        setState(() => _resolvingStatus = 'Trying ${provider.displayName}...');
        final result = await load(provider);
        selection = result.success && (result.videoLinks?.isNotEmpty ?? false)
            ? ProviderSelection(
                index: selectedIndex,
                provider: provider,
                result: result,
              )
            : null;
      }

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
      final autoSelectedProvider = selection!;
      // Auto may reorder sources using health data. PlayerScreen still needs
      // an index into the original provider list for its switcher.
      final resolvedSelection = selectedIndex == -1
          ? ProviderSelection(
              index: providers.indexOf(autoSelectedProvider.provider),
              provider: autoSelectedProvider.provider,
              result: autoSelectedProvider.result,
            )
          : autoSelectedProvider;

      await context.read<WatchlistProvider>().markWatched(widget.item.type, widget.item.id);
      await context.read<RecentlyWatchedProvider>().record(item: widget.item, season: season, episode: episode);

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            title: widget.item.title + (season != null ? ' - S${season}E$episode' : ''),
            mediaType: widget.item.type,
            tmdbId: widget.item.id,
            season: season,
            episode: episode,
            providers: providers,
            initialProviderIndex: resolvedSelection.index,
            initialResult: resolvedSelection.result,
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

  Future<_StreamChoice?> _showProviderPicker(List<VideoProvider> providers) {
    // Fetch once for this picker opening. This is the same server-side
    // snapshot Auto consults immediately after the user selects it.
    final healthFuture = ScraperApi(AppConfig.scraperBaseUrl)
        .getProviderHealthStatus();
    return showModalBottomSheet<_StreamChoice>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppTheme.surface,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .62,
          child: FutureBuilder<ProviderHealthSnapshot>(
            future: healthFuture,
            builder: (context, healthSnapshot) {
              final healthById = {
                for (final provider in healthSnapshot.data?.providers ?? const <ProviderHealthResult>[])
                  provider.id: provider,
              };
              return DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    const ListTile(
                      title: Text('Choose a stream source', style: AppTheme.sectionHeaderStyle),
                    ),
                    const TabBar(
                      tabs: [
                        Tab(text: 'Scraper streams'),
                        Tab(text: 'Embeds'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          ListView(
                            children: [
                              if (healthSnapshot.connectionState == ConnectionState.waiting)
                                const ListTile(
                                  leading: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                  title: Text('Checking provider status…'),
                                )
                              else if (healthSnapshot.hasError)
                                const ListTile(
                                  leading: Icon(Icons.cloud_off_outlined, color: AppTheme.warning),
                                  title: Text('Provider status unavailable'),
                                  subtitle: Text('Auto will still test sources directly.', style: AppTheme.metaStyle),
                                ),
                              if (providers.isNotEmpty) ...[
                                ListTile(
                                  leading: const Icon(Icons.auto_awesome, color: AppTheme.accent),
                                  title: const Text('Auto'),
                                  subtitle: Text(
                                    healthSnapshot.data == null
                                        ? 'Tests sources directly to find a playable one'
                                        : '${healthSnapshot.data!.online}/${healthSnapshot.data!.total} providers online · checks this title next',
                                    style: AppTheme.metaStyle,
                                  ),
                                  onTap: () => Navigator.of(sheetContext)
                                      .pop(const _StreamChoice.scraper(-1)),
                                ),
                                const Divider(height: 1, color: AppTheme.border),
                                for (var index = 0;
                                    index < providers.length;
                                    index++)
                                  _ProviderChoiceTile(
                                    provider: providers[index],
                                    health: healthById[providers[index].apiId ?? ''],
                                    onTap: () => Navigator.of(sheetContext)
                                        .pop(_StreamChoice.scraper(index)),
                                  ),
                              ] else
                                const ListTile(
                                  leading: Icon(Icons.cloud_off_outlined, color: AppTheme.textSecondary),
                                  title: Text('No scraper streams available'),
                                  subtitle: Text('Check the scraper connection, or choose an embed.', style: AppTheme.metaStyle),
                                ),
                            ],
                          ),
                          ListView(
                            children: [
                              const ListTile(
                                title: Text('Embeds'),
                                subtitle: Text('Open a provider in the embedded player.', style: AppTheme.metaStyle),
                              ),
                              for (var index = 0; index < embedProviders.length; index++)
                                ListTile(
                                  leading: const Icon(Icons.open_in_browser_outlined, color: AppTheme.textSecondary),
                                  title: Text(embedProviders[index].name),
                                  subtitle: const Text('Open embed player', style: AppTheme.metaStyle),
                                  onTap: () => Navigator.of(sheetContext).pop(_StreamChoice.embed(index)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Fallback for when every provider fails: an in-app, ad-blocked WebView
  /// showing a provider's real embed page (see WebViewPlayerScreen), so the
  /// user still has something to watch instead of a dead end.
  void _openWebViewFallback({int? season, int? episode}) {
    _openWebViewEmbed(0, season: season, episode: episode);
  }

  void _openWebViewEmbed(int providerIndex, {int? season, int? episode}) {
    // An embed is still playback. Keep an already-bookmarked title at the
    // front of this device's watchlist just like native playback does.
    context.read<WatchlistProvider>().markWatched(widget.item.type, widget.item.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebViewPlayerScreen(
          title: widget.item.title,
          type: widget.item.type,
          tmdbId: widget.item.id,
          season: season,
          episode: episode,
          initialProviderIndex: providerIndex,
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
          final flutterView = View.of(context);
          final displayWidth = flutterView.display.size.width / flutterView.devicePixelRatio;
          final displayHeight = flutterView.display.size.height / flutterView.devicePixelRatio;
          final isResizableWindow =
              Theme.of(context).platform == TargetPlatform.iOS &&
              MediaQuery.sizeOf(context).shortestSide >= 600 &&
              (MediaQuery.sizeOf(context).width < displayWidth - 1 ||
                  MediaQuery.sizeOf(context).height < displayHeight - 1);
          // iPadOS draws its compact-window controls over the upper-left
          // corner but does not expose their bounds as a safe-area inset.
          // Keep the page exactly unchanged and move only the Back button
          // below them while the app is in a resized window.
          // iPad already reports most of the title-bar height as padding.
          // This is only the small extra nudge needed to clear its controls.
          final backButtonOffset = isResizableWindow ? 25.0 : 0.0;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: isDesktop ? 420 : 260,
                pinned: true,
                automaticallyImplyLeading: false,
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
                      Positioned(
                        top: MediaQuery.paddingOf(context).top + backButtonOffset,
                        left: 8,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back),
                          tooltip: 'Back',
                          onPressed: () => Navigator.of(context).maybePop(),
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
                      FadeInOnScroll(
                        child: Text(detail.item.title, style: Theme.of(context).textTheme.headlineSmall),
                      ),
                      const SizedBox(height: 6),
                      FadeInOnScroll(
                        delay: const Duration(milliseconds: 55),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            if (detail.item.year.isNotEmpty) _Chip(detail.item.year),
                            if (detail.runtimeMinutes != null) _Chip('${detail.runtimeMinutes}m'),
                            _Chip('★ ${detail.item.voteAverage.toStringAsFixed(1)}', accent: true),
                            for (final g in detail.genres.take(3)) _Chip(g),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      FadeInOnScroll(
                        delay: const Duration(milliseconds: 110),
                        child: Text(
                          detail.item.overview ?? '',
                          style: const TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
                      const SizedBox(height: 20),
                      FadeInOnScroll(
                        delay: const Duration(milliseconds: 165),
                        child: !isTv
                            ? ElevatedButton.icon(
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
                            : _SeasonEpisodePicker(
                                seasons: detail.seasons,
                                selectedSeason: _selectedSeason,
                                episodes: _episodes,
                                loadingEpisodes: _loadingEpisodes,
                                resolving: _resolving,
                                resolvingStatus: _resolvingStatus,
                                onSeasonChanged: _onSeasonChanged,
                                onPlayEpisode: (episode) => _play(season: _selectedSeason, episode: episode),
                              ),
                        ),
                    ],
                  ),
                ),
              ),
              if (detail.collectionItems.isNotEmpty)
                SliverToBoxAdapter(
                  child: FadeInOnScroll(
                    delay: const Duration(milliseconds: 55),
                    child: MediaRow(
                      title: detail.collectionName ?? 'Collection',
                      items: detail.collectionItems,
                      onItemTap: widget.onSelectRelated,
                    ),
                  ),
                ),
              if (detail.cast.isNotEmpty)
                SliverToBoxAdapter(
                  child: FadeInOnScroll(
                    delay: const Duration(milliseconds: 80),
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
                                  style: AppTheme.resolvedStyle(
                                    context,
                                    AppTheme.castNameStyle,
                                    TextCategory.castDetails,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: FadeInOnScroll(
                  delay: const Duration(milliseconds: 80),
                  child: MediaRow(
                    title: 'More Like This',
                    items: detail.similar,
                    onItemTap: widget.onSelectRelated,
                  ),
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

class _ProviderChoiceTile extends StatelessWidget {
  const _ProviderChoiceTile({
    required this.provider,
    required this.health,
    required this.onTap,
  });

  final VideoProvider provider;
  final ProviderHealthResult? health;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final online = health?.isOnline == true;
    final offline = health?.isOffline == true;
    final color = online
        ? AppTheme.success
        : offline
            ? AppTheme.error
            : AppTheme.textSecondary;
    final healthText = health == null
        ? 'Status not available'
        : online
            ? 'Online${health!.requestTime > Duration.zero ? ' · ${health!.requestTime.inMilliseconds} ms' : ''}'
            : offline
                ? 'Offline'
                : 'Untested';
    final content = provider.content?.trim();
    return ListTile(
      leading: Icon(
        online ? Icons.check_circle_outline : Icons.play_circle_outline,
        color: color,
      ),
      title: Text(provider.displayName),
      subtitle: Text(
        content == null || content.isEmpty ? healthText : '$healthText · $content',
        style: AppTheme.metaStyle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: health == null
          ? null
          : Text(
              online ? 'Online' : offline ? 'Offline' : 'Untested',
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
      onTap: onTap,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {this.accent = false});
  final String label;

  /// Set for the star-rating chip so it reads as a highlight (gold pill,
  /// bold dark-on-gold text) rather than a plain metadata tag like the
  /// year/runtime/genre chips next to it.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent ? AppTheme.accent : AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: accent
            ? AppTheme.badgeStyle
            : AppTheme.resolvedStyle(context, AppTheme.metaStyle, TextCategory.info),
      ),
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
                FadeInOnScroll(
                  colorSweep: false,
                  delay: Duration(milliseconds: 28 * (i % 8)),
                  child: _EpisodeRow(
                    episode: episodes[i],
                    enabled: !resolving,
                    onTap: () => onPlayEpisode(episodes[i].episodeNumber),
                  ),
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
