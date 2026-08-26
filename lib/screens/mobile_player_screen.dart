import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/config.dart';
import '../models/media_item.dart';
import '../core/theme.dart';
import '../models/external_subtitle.dart';
import '../services/external_subtitle_service.dart';
import '../video_providers/common.dart';
import '../video_providers/names.dart';
import '../video_providers/provider_loader.dart';
import 'webview_player_screen.dart';

/// Android/iOS playback screen, built on better_player_plus (ExoPlayer on
/// Android, AVPlayer on iOS) - the same engine flixquest's own player uses.
///
/// This exists as a separate engine from DesktopPlayerScreen (media_kit)
/// because ExoPlayer's native HTTP source handling - adaptive retry,
/// chunked seeking, malformed Content-Range recovery - is meaningfully more
/// resilient against the flaky scraped CDNs this app plays from than
/// libmpv is on Android specifically. That gap is what was behind seeking
/// hanging/restarting/no-op'ing on mobile even after tuning media_kit's own
/// network settings - it's an engine-level difference, not a config one.
class MobilePlayerScreen extends StatefulWidget {
  const MobilePlayerScreen({
    super.key,
    required this.title,
    required this.mediaType,
    required this.tmdbId,
    this.season,
    this.episode,
    required this.providers,
    required this.initialProviderIndex,
    required this.initialResult,
  });

  final String title;
  final MediaType mediaType;
  final int tmdbId;
  final int? season;
  final int? episode;
  final List<VideoProvider> providers;
  final int initialProviderIndex;
  final ProviderLoadResult initialResult;

  @override
  State<MobilePlayerScreen> createState() => _MobilePlayerScreenState();
}

class _MobilePlayerScreenState extends State<MobilePlayerScreen> {
  BetterPlayerController? _controller;

  late int _providerIndex;
  late ProviderLoadResult _result;

  bool _loading = true;
  bool _switchingProvider = false;
  String? _fatalError;

  Timer? _freezeWatchdog;
  Duration _lastKnownPosition = Duration.zero;
  DateTime _lastProgressAt = DateTime.now();
  bool _showFrozenHint = false;

  // Subtitles fetched directly from Wyzie Subs by TMDB id/season/episode -
  // same ExternalSubtitleService used by DesktopPlayerScreen, independent of
  // whichever provider ends up playing. Ported from flixquest's
  // ExternalSubtitleService/PlayerExternalSubtitles pattern.
  List<ExternalSubtitle> _externalSubtitles = [];
  bool _fetchedExternalSubtitles = false;
  bool _loadingExternalSubtitles = false;

  @override
  void initState() {
    super.initState();
    _providerIndex = widget.initialProviderIndex;
    _result = widget.initialResult;
    WakelockPlus.enable();
    _setupController();
  }

  @override
  void dispose() {
    _freezeWatchdog?.cancel();
    WakelockPlus.disable();
    _controller?.dispose();
    super.dispose();
  }

  void _setupController() {
    _controller = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: true,
        fit: BoxFit.contain,
        autoDispose: false,
        allowedScreenSleep: false,
        fullScreenByDefault: false,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          // Default is Colors.black87 - noticeably darker than most
          // players' tap-to-reveal overlay. Lightened to 40% opacity so
          // the video stays more visible behind the controls.
          controlBarColor: Colors.black.withOpacity(0.4),
          enableFullscreen: true,
          enablePlaybackSpeed: true,
          enableSubtitles: true,
          enableSkips: true,
          overflowMenuCustomItems: [
            BetterPlayerOverflowMenuItem(
              Icons.subtitles_outlined,
              'Search subtitles',
              _showExternalSubtitlesSheet,
            ),
            if (widget.providers.length > 1)
              BetterPlayerOverflowMenuItem(
                Icons.swap_horiz,
                'Switch provider',
                _showProviderSwitcher,
              ),
            BetterPlayerOverflowMenuItem(
              Icons.open_in_browser,
              'Watch via embedded player',
              _openWebViewFallback,
            ),
          ],
        ),
        errorBuilder: (context, errorMessage) => _PlaybackErrorView(
          message: errorMessage ?? 'Playback failed',
          hasOtherProviders: widget.providers.length > 1,
          onTryAnotherSource: () =>
              _switchProvider((_providerIndex + 1) % widget.providers.length),
          onWatchEmbedded: _openWebViewFallback,
        ),
      ),
    );
    _controller!.addEventsListener(_onPlayerEvent);
    unawaited(_openCurrentResult());
  }

  BetterPlayerVideoFormat? _inferFormat(RegularVideoLinks link) {
    if (link.isM3U8 == true) return BetterPlayerVideoFormat.hls;
    if (link.isDash == true) return BetterPlayerVideoFormat.dash;
    final lower = (link.url ?? '').toLowerCase();
    if (lower.contains('.m3u8')) return BetterPlayerVideoFormat.hls;
    if (lower.contains('.mpd')) return BetterPlayerVideoFormat.dash;
    return null;
  }

  Future<void> _openCurrentResult() async {
    final links = _result.videoLinks ?? const [];
    if (links.isEmpty) {
      setState(() {
        _loading = false;
        _fatalError = 'No playable source for this title.';
      });
      return;
    }

    final primary = links.first;
    final resolutions = <String, String>{
      for (final link in links)
        if (link.url != null) (link.quality ?? 'auto'): link.url!,
    };

    final dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      primary.url!,
      headers: primary.headers,
      videoFormat: _inferFormat(primary),
      resolutions: resolutions.length > 1 ? resolutions : null,
      subtitles: [
        for (final sub in _result.subtitleLinks ?? const [])
          if (sub.url != null)
            BetterPlayerSubtitlesSource(
              type: BetterPlayerSubtitlesSourceType.network,
              urls: [sub.url!],
              name: sub.language ?? 'Unknown',
              headers: sub.headers,
            ),
      ],
    );

    setState(() {
      _loading = true;
      _fatalError = null;
      _showFrozenHint = false;
    });

    try {
      await _controller!.setupDataSource(dataSource);
      _armFreezeWatchdog();
    } catch (error) {
      if (mounted) setState(() => _fatalError = 'Playback failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onPlayerEvent(BetterPlayerEvent event) {
    if (event.betterPlayerEventType == BetterPlayerEventType.exception) {
      // The errorBuilder above already renders a full-screen fallback for
      // fatal exceptions - nothing extra to do here.
      return;
    }
  }

  // ExoPlayer's own seek/buffer handling is far more resilient than
  // libmpv's on these scraped sources, so unlike DesktopPlayerScreen this
  // doesn't need per-seek retry logic - just a generic "has playback been
  // completely frozen for a while" watchdog as a safety net, since a
  // genuinely dead upstream can still hang indefinitely either way.
  void _armFreezeWatchdog() {
    _freezeWatchdog?.cancel();
    _lastKnownPosition = Duration.zero;
    _lastProgressAt = DateTime.now();
    _freezeWatchdog = Timer.periodic(const Duration(seconds: 5), (_) {
      final controller = _controller;
      if (controller == null || !mounted) return;
      final isPlaying = controller.isPlaying() ?? false;
      final position =
          controller.videoPlayerController?.value.position ?? Duration.zero;

      if (!isPlaying) {
        // Paused/buffering on purpose - don't count this against the
        // freeze window, just don't update the reference point either.
        return;
      }

      if ((position - _lastKnownPosition).abs() > const Duration(seconds: 1)) {
        _lastKnownPosition = position;
        _lastProgressAt = DateTime.now();
        if (_showFrozenHint) setState(() => _showFrozenHint = false);
        return;
      }

      final frozenFor = DateTime.now().difference(_lastProgressAt);
      if (frozenFor > const Duration(seconds: 15) && !_showFrozenHint) {
        setState(() => _showFrozenHint = true);
      }
    });
  }

  Future<void> _switchProvider(int index) async {
    if (index == _providerIndex || _switchingProvider) return;
    final provider = widget.providers[index];
    setState(() => _switchingProvider = true);

    final result = widget.mediaType == MediaType.movie
        ? await ProviderLoader.loadMovieFromProvider(
            provider: provider,
            movieId: widget.tmdbId,
            scraperApiUrl: AppConfig.scraperBaseUrl,
          )
        : await ProviderLoader.loadTVFromProvider(
            provider: provider,
            tvId: widget.tmdbId,
            seasonNumber: widget.season!,
            episodeNumber: widget.episode!,
            scraperApiUrl: AppConfig.scraperBaseUrl,
          );

    if (!mounted) return;
    setState(() => _switchingProvider = false);

    if (!result.success || (result.videoLinks?.isEmpty ?? true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${provider.displayName} has no playable source right now.')),
      );
      return;
    }

    setState(() {
      _providerIndex = index;
      _result = result;
      _showFrozenHint = false;
    });
    await _openCurrentResult();
  }

  void _showProviderSwitcher() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141414),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Switch provider', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            for (var i = 0; i < widget.providers.length; i++)
              ListTile(
                leading: Icon(
                  i == _providerIndex ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: i == _providerIndex ? AppTheme.accent : Colors.white54,
                ),
                title: Text(widget.providers[i].displayName, style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _switchProvider(i);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchExternalSubtitles(void Function(void Function()) setSheetState) async {
    try {
      final subs = widget.mediaType == MediaType.movie
          ? await ExternalSubtitleService.fetchMovieSubtitles(widget.tmdbId)
          : await ExternalSubtitleService.fetchTVSubtitles(
              widget.tmdbId,
              widget.season!,
              widget.episode!,
            );
      _externalSubtitles = subs;
    } catch (_) {
      _externalSubtitles = const [];
    } finally {
      _fetchedExternalSubtitles = true;
      _loadingExternalSubtitles = false;
      setSheetState(() {});
    }
  }

  // Mirrors flixquest's PlayerExternalSubtitles: search Wyzie Subs by TMDB
  // id/season/episode and add whichever the user taps to the controller's
  // own subtitle source list, so it shows up in BetterPlayer's built-in
  // subtitle picker immediately afterwards.
  void _showExternalSubtitlesSheet() {
    var sheetOpen = true;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141414),
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          if (!_fetchedExternalSubtitles && !_loadingExternalSubtitles) {
            _loadingExternalSubtitles = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (sheetOpen) _fetchExternalSubtitles(setSheetState);
            });
          }
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Search subtitles', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  if (_loadingExternalSubtitles)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
                    )
                  else if (_externalSubtitles.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No external subtitles found for this title.', style: TextStyle(color: Colors.white54)),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _externalSubtitles.length,
                        itemBuilder: (context, index) {
                          final sub = _externalSubtitles[index];
                          return ListTile(
                            leading: const Icon(Icons.closed_caption_outlined, color: Colors.white70),
                            title: Text(sub.displayName, style: const TextStyle(color: Colors.white)),
                            subtitle: Text(sub.source, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                            onTap: () {
                              _controller?.setupSubtitleSource(
                                BetterPlayerSubtitlesSource(
                                  type: BetterPlayerSubtitlesSourceType.network,
                                  urls: [sub.url],
                                  name: sub.displayName,
                                ),
                              );
                              Navigator.pop(sheetContext);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() => sheetOpen = false);
  }

  void _openWebViewFallback() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebViewPlayerScreen(
          title: widget.title,
          type: widget.mediaType,
          tmdbId: widget.tmdbId,
          season: widget.season,
          episode: widget.episode,
        ),
      ),
    );
  }

  // Explicit back handling: without this, leaving via the system back
  // gesture/button pops the route while BetterPlayerController's dispose()
  // is still tearing down ExoPlayer in the background, so audio/video can
  // keep going for a moment after the landing page is already back on
  // screen. Pausing first (near-instant) before popping closes that gap,
  // and this is also what the new on-screen back button below calls.
  Future<void> _handleBack() async {
    try {
      await _controller?.pause();
    } catch (_) {
      // Best-effort - still proceed to pop even if pause failed/raced.
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_fatalError != null) {
      return PopScope(
        canPop: false,
        onPopInvoked: (didPop) {
          if (!didPop) _handleBack();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              children: [
                _PlaybackErrorView(
                  message: _fatalError!,
                  hasOtherProviders: widget.providers.length > 1,
                  onTryAnotherSource: () =>
                      _switchProvider((_providerIndex + 1) % widget.providers.length),
                  onWatchEmbedded: _openWebViewFallback,
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: _CircleIconButton(icon: Icons.arrow_back, onTap: _handleBack),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
        fit: StackFit.expand,
        children: [
          if (_controller != null) BetterPlayer(controller: _controller!),
          Positioned(
            top: 8,
            left: 8,
            child: SafeArea(
              child: _CircleIconButton(icon: Icons.arrow_back, onTap: _handleBack),
            ),
          ),
          if (_loading || _switchingProvider)
            const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
          if (_showFrozenHint && !_loading)
            Positioned(
              left: 24,
              right: 24,
              bottom: 100,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "This source seems stuck - it may be down.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        if (widget.providers.length > 1)
                          ElevatedButton(
                            onPressed: () =>
                                _switchProvider((_providerIndex + 1) % widget.providers.length),
                            child: const Text('Try another source'),
                          ),
                        OutlinedButton(
                          onPressed: _openWebViewFallback,
                          child: const Text('Watch via embedded player'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
        ),
      ),
    );
  }

}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _PlaybackErrorView extends StatelessWidget {
  const _PlaybackErrorView({
    required this.message,
    required this.hasOtherProviders,
    required this.onTryAnotherSource,
    required this.onWatchEmbedded,
  });

  final String message;
  final bool hasOtherProviders;
  final VoidCallback onTryAnotherSource;
  final VoidCallback onWatchEmbedded;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (hasOtherProviders)
                  ElevatedButton(onPressed: onTryAnotherSource, child: const Text('Try another source')),
                OutlinedButton(onPressed: onWatchEmbedded, child: const Text('Watch via embedded player')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
