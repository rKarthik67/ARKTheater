import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/config.dart';
import '../models/media_item.dart';
import '../core/theme.dart';
import '../models/external_subtitle.dart';
import '../services/external_subtitle_service.dart';
import '../services/playback_position_service.dart';
import '../services/recently_watched_service.dart';
import '../services/subtitle_download_history_service.dart';
import '../services/subtitle_style_service.dart';
import '../utils/subtitle_sync.dart';
import '../widgets/subtitle_style_sheet.dart';
import '../widgets/liquid_glass.dart';
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
  final _playbackPosition = PlaybackPositionService();

  // Once a title/episode is fully watched, PlaybackPositionService.save()
  // clears its resume spot and reports it as finished - at that point it
  // no longer belongs in "Recently Watched" either, since there's nothing
  // left to continue.
  void _onPositionSaved(bool finished) {
    if (!finished) return;
    unawaited(RecentlyWatchedService().removeItem(
      widget.mediaType,
      widget.tmdbId,
      season: widget.season,
      episode: widget.episode,
    ));
    // Subtitles downloaded for this specific episode/movie have nothing
    // left to be "already downloaded for" once it's finished - forget
    // them so they stop showing the highlight (a subtitle also used by a
    // still-unfinished episode stays tracked there).
    unawaited(_subtitleDownloadHistory.clearForMedia(
      mediaType: widget.mediaType,
      tmdbId: widget.tmdbId,
      season: widget.season,
      episode: widget.episode,
    ));
  }

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
  String? _externalSubtitlesError;
  bool _fetchedExternalSubtitles = false;
  bool _loadingExternalSubtitles = false;

  // Manual subtitle sync offset, applied to whichever subtitle was picked
  // from the "Search subtitles" sheet below. better_player_plus has no
  // built-in delay/offset knob (unlike mpv's `sub-delay` used on desktop),
  // so this works by re-fetching the raw subtitle text once, keeping it
  // around, and re-shifting+reloading it as an in-memory subtitle source
  // every time the offset changes (see shiftSubtitleTimings). Positive =
  // subtitles appear later, negative = earlier. Reset whenever a new video
  // loads (see _openCurrentResult) so an offset dialed in for one title
  // doesn't silently carry into the next.
  double _subtitleDelaySeconds = 0.0;
  String? _activeSubtitleRawContent;
  String? _activeSubtitleName;
  final _subtitleDownloadHistory = SubtitleDownloadHistoryService();
  Set<String> _downloadedSubtitleIds = const {};
  // The single most recently picked subtitle - gets its own distinct
  // highlight (light yellow + "Last downloaded" label) in the picker,
  // separate from every other past pick's plain "already tried" tint.
  String? _lastDownloadedSubtitleId;

  // User-customizable subtitle text color/background/font size - loaded
  // BEFORE the player controller is first built (see initState) so
  // playback always starts with the right appearance from frame one,
  // rather than flashing default styling and then correcting itself.
  SubtitleStyle _subtitleStyle = SubtitleStyle.defaultStyle;
  // What's actually baked into the live BetterPlayerController right now -
  // compared against _subtitleStyle when the appearance sheet closes, so
  // a visit that changes nothing (or changes something and changes it
  // back) never triggers a needless reload.
  SubtitleStyle _appliedSubtitleStyle = SubtitleStyle.defaultStyle;

  @override
  void initState() {
    super.initState();
    _providerIndex = widget.initialProviderIndex;
    _result = widget.initialResult;
    WakelockPlus.enable();
    _loadSubtitleDownloadHistory();
    _initSubtitleStyleThenController();
  }

  Future<void> _initSubtitleStyleThenController() async {
    _subtitleStyle = await SubtitleStyleService().load();
    _appliedSubtitleStyle = _subtitleStyle;
    if (!mounted) return;
    _setupController();
  }

  Future<void> _loadSubtitleDownloadHistory() async {
    final results = await Future.wait([
      _subtitleDownloadHistory.loadDownloadedIds(),
      _subtitleDownloadHistory.loadLastDownloadedId(),
    ]);
    if (!mounted) return;
    setState(() {
      _downloadedSubtitleIds = results[0] as Set<String>;
      _lastDownloadedSubtitleId = results[1] as String?;
    });
  }

  // Fired exactly once, when the "Apply" button in the appearance sheet is
  // pressed (see subtitle_style_sheet.dart) - every swatch tap/slider move
  // before that only edits the sheet's own local draft, so nothing here
  // runs until the user has actually confirmed a choice. Persists the
  // preference immediately, but does NOT touch the live player here -
  // better_player_plus has no API to update subtitle styling on a live
  // controller (unlike mpv's sub-color/sub-back-color properties used on
  // desktop, which apply instantly), so actually applying it means
  // rebuilding the whole BetterPlayerController: see _reloadIfStyleChanged,
  // which does that once the sheet closes and only if something changed.
  void _onSubtitleStylePreviewChanged(SubtitleStyle style) {
    setState(() => _subtitleStyle = style);
    unawaited(SubtitleStyleService().save(style));
  }

  Future<void> _reloadIfStyleChanged() async {
    if (_subtitleStyle == _appliedSubtitleStyle) return;
    final resumePosition = _controller?.videoPlayerController?.value.position;
    // autoDispose is false on this controller (see _setupController) so a
    // plain dispose() silently no-ops - the old controller (and its audio
    // track) would keep running underneath the brand new one _setupController
    // is about to create, which is what produced the "audio mixes up from
    // the beginning while video keeps playing" symptom. forceDispose makes
    // it actually tear down first.
    _controller?.dispose(forceDispose: true);
    _appliedSubtitleStyle = _subtitleStyle;
    _setupController(resumeAt: resumePosition, preserveActiveSubtitle: true);
  }

  void _showSubtitleStyleSheet() {
    showSubtitleStyleSheet(
      context: context,
      current: _subtitleStyle,
      onChanged: _onSubtitleStylePreviewChanged,
    ).then((_) => _reloadIfStyleChanged());
  }

  @override
  void dispose() {
    _freezeWatchdog?.cancel();
    WakelockPlus.disable();
    final videoValue = _controller?.videoPlayerController?.value;
    if (videoValue != null) {
      unawaited(_playbackPosition.save(
        mediaType: widget.mediaType,
        tmdbId: widget.tmdbId,
        season: widget.season,
        episode: widget.episode,
        position: videoValue.position,
        duration: videoValue.duration ?? Duration.zero,
      ).then(_onPositionSaved));
    }
    _controller?.dispose(forceDispose: true);
    super.dispose();
  }

  String _formatDuration(Duration d) {
    if (d.isNegative || d == Duration.zero) return '0:00';
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    final mm = hours > 0 ? minutes.toString().padLeft(2, '0') : minutes.toString();
    final ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  void _setupController({Duration? resumeAt, bool preserveActiveSubtitle = false}) {
    _controller = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: true,
        fit: BoxFit.contain,
        autoDispose: false,
        allowedScreenSleep: false,
        fullScreenByDefault: false,
        subtitlesConfiguration: BetterPlayerSubtitlesConfiguration(
          fontSize: _subtitleStyle.fontSize,
          fontColor: _subtitleStyle.fontColor,
          backgroundColor: _subtitleStyle.backgroundColor,
        ),
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
            BetterPlayerOverflowMenuItem(
              Icons.format_color_text,
              'Subtitle appearance',
              _showSubtitleStyleSheet,
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
    unawaited(_openCurrentResult(resumeAt: resumeAt, preserveActiveSubtitle: preserveActiveSubtitle));
  }

  BetterPlayerVideoFormat? _inferFormat(RegularVideoLinks link) {
    if (link.isM3U8 == true) return BetterPlayerVideoFormat.hls;
    if (link.isDash == true) return BetterPlayerVideoFormat.dash;
    final lower = (link.url ?? '').toLowerCase();
    if (lower.contains('.m3u8')) return BetterPlayerVideoFormat.hls;
    if (lower.contains('.mpd')) return BetterPlayerVideoFormat.dash;
    return null;
  }

  Future<void> _openCurrentResult({Duration? resumeAt, bool preserveActiveSubtitle = false}) async {
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
      // better_player_plus's own default here is maxBufferMs: 6553600 -
      // about 109 minutes of media. On these scraped sources that meant
      // ExoPlayer would keep buffering (and holding decoded frames/samples
      // in memory) far beyond anything actually needed for smooth
      // playback, which - on top of largeHeap="true" already being turned
      // on - was very likely the real driver behind the OOM crash on long
      // playback sessions (the QC2V4l2Decoder "output buffer timedout"
      // warnings growing over minutes, from the earlier crash log, match a
      // buffer backlog like this). Capping it to a normal 30s window keeps
      // memory bounded instead of just raising the ceiling further.
      bufferingConfiguration: const BetterPlayerBufferingConfiguration(
        minBufferMs: 15000,
        maxBufferMs: 30000,
        bufferForPlaybackMs: 2500,
        bufferForPlaybackAfterRebufferMs: 5000,
      ),
    );

    // A new data source is loading (fresh title, or a provider/quality
    // switch) - any manually-dialed subtitle sync offset was for the
    // previous subtitle file and shouldn't silently carry over. Exception:
    // a reload triggered by _reloadIfStyleChanged (changing subtitle
    // color/background/font size) is still the SAME title/episode with
    // the SAME externally-picked subtitle still active - wiping it there
    // meant every appearance change silently dropped whatever subtitle
    // you'd searched for and picked, forcing you to search and pick it
    // again. preserveActiveSubtitle keeps it instead.
    if (!preserveActiveSubtitle) {
      _subtitleDelaySeconds = 0.0;
      _activeSubtitleRawContent = null;
      _activeSubtitleName = null;
    }

    setState(() {
      _loading = true;
      _fatalError = null;
      _showFrozenHint = false;
    });

    try {
      await _controller!.setupDataSource(dataSource);

      // The freshly-built controller above only knows about the
      // provider's own embedded subtitle tracks (dataSource.subtitles) -
      // if an externally-picked (Wyzie) subtitle was active before this
      // reload, put it back now exactly as it was, offset included.
      if (preserveActiveSubtitle && _activeSubtitleRawContent != null) {
        _reapplySubtitleWithOffset();
      }

      // Resume where playback left off: either the position carried over
      // from a provider switch (resumeAt, so switching providers mid-title
      // doesn't throw away progress), or - on the very first load - a spot
      // saved from a previous session for this exact title/episode.
      final fromStorage = resumeAt == null;
      final target = resumeAt ??
          await _playbackPosition.load(
            mediaType: widget.mediaType,
            tmdbId: widget.tmdbId,
            season: widget.season,
            episode: widget.episode,
          );
      if (target != null && target > const Duration(seconds: 2)) {
        await _controller!.seekTo(target);
        if (fromStorage && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Resumed from ${_formatDuration(target)}')),
          );
        }
      }

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
      final videoValue = controller.videoPlayerController?.value;
      final position = videoValue?.position ?? Duration.zero;

      // Saved every tick regardless of play/pause state, so pausing (or
      // the app going to the background) doesn't lose recent progress.
      unawaited(_playbackPosition.save(
        mediaType: widget.mediaType,
        tmdbId: widget.tmdbId,
        season: widget.season,
        episode: widget.episode,
        position: position,
        duration: videoValue?.duration ?? Duration.zero,
      ).then(_onPositionSaved));

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
    final resumePosition = _controller?.videoPlayerController?.value.position;
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
    await _openCurrentResult(resumeAt: resumePosition);
  }

  void _showProviderSwitcher() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      // Without this, a modal bottom sheet caps itself at roughly half the
      // screen height and its content (a plain, non-scrolling Column below)
      // just gets clipped past that - there was no scroll view at all, so
      // once the provider list grew past what fit in that half-screen cap
      // (it's now 10 providers) the rest were simply unreachable, not just
      // hard to drag to. isScrollControlled lets the sheet grow with its
      // content instead of hard-capping it.
      isScrollControlled: true,
      builder: (sheetContext) => LiquidGlassSheet(
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Switch provider', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              // Bounded + scrollable (matching the "Search subtitles" sheet's
              // pattern below) so a long provider list scrolls within the
              // sheet instead of pushing later entries off-screen entirely.
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.providers.length,
                  itemBuilder: (context, i) => ListTile(
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
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  // Re-renders whatever subtitle is currently active (fetched raw text
  // held in _activeSubtitleRawContent) shifted by the current sync offset,
  // as an in-memory BetterPlayer subtitle source - better_player_plus has
  // no native delay/offset knob, so the shift has to happen on the text
  // itself rather than as a player property (contrast with the desktop
  // player's mpv sub-delay, which does support that natively).
  void _reapplySubtitleWithOffset() {
    final raw = _activeSubtitleRawContent;
    if (raw == null) return;
    _controller?.setupSubtitleSource(
      BetterPlayerSubtitlesSource(
        type: BetterPlayerSubtitlesSourceType.memory,
        content: shiftSubtitleTimings(raw, _subtitleDelaySeconds),
        name: _activeSubtitleName ?? 'Subtitle',
      ),
    );
  }

  // +/- 0.25s per tap. Only meaningful once a subtitle picked from the
  // "Search subtitles" list has been fetched (see _applyExternalSubtitle) -
  // there's nothing to shift before that.
  void _adjustSubtitleDelay(double deltaSeconds, void Function(void Function()) setSheetState) {
    if (_activeSubtitleRawContent == null) return;
    _subtitleDelaySeconds = (_subtitleDelaySeconds + deltaSeconds).clamp(-30.0, 30.0);
    _reapplySubtitleWithOffset();
    setSheetState(() {});
  }

  // Fetches the chosen Wyzie subtitle's raw text once (instead of just
  // pointing BetterPlayer at the URL directly) so it can be re-shifted
  // in-place whenever the user nudges the sync offset afterwards. Falls
  // back to loading it as a plain network source if the fetch fails, so a
  // transient network hiccup here doesn't leave the user with no subtitle
  // at all - it just won't be sync-adjustable in that case.
  Future<void> _applyExternalSubtitle(ExternalSubtitle sub) async {
    _subtitleDelaySeconds = 0.0;
    _activeSubtitleRawContent = null;
    _activeSubtitleName = sub.displayName;
    unawaited(_subtitleDownloadHistory.markDownloaded(
                                mediaType: widget.mediaType,
                                tmdbId: widget.tmdbId,
                                season: widget.season,
                                episode: widget.episode,
                                subtitleId: sub.id,
                              ));
    if (mounted) {
      setState(() {
        _downloadedSubtitleIds = {..._downloadedSubtitleIds, sub.id};
        _lastDownloadedSubtitleId = sub.id;
      });
    }
    try {
      final response = await http.get(Uri.parse(sub.url)).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        _activeSubtitleRawContent = response.body;
        _reapplySubtitleWithOffset();
        return;
      }
    } catch (_) {
      // Fall through to the network-source fallback below.
    }
    _controller?.setupSubtitleSource(
      BetterPlayerSubtitlesSource(
        type: BetterPlayerSubtitlesSourceType.network,
        urls: [sub.url],
        name: sub.displayName,
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
      _externalSubtitlesError = null;
    } catch (error) {
      _externalSubtitles = const [];
      // Surfaced in the sheet below instead of collapsing into the same
      // "no subtitles found" message a genuinely empty result gets - a
      // failed search (bad/expired key, Wyzie Subs down, no network) looks
      // very different from a title that just has no subtitles.
      _externalSubtitlesError = error.toString();
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
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          if (!_fetchedExternalSubtitles && !_loadingExternalSubtitles) {
            _loadingExternalSubtitles = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (sheetOpen) _fetchExternalSubtitles(setSheetState);
            });
          }
          return LiquidGlassSheet(
            child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Search subtitles', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                  if (_activeSubtitleRawContent != null) ...[
                    const SizedBox(height: 12),
                    // Only shown once a subtitle fetched from this sheet is
                    // active - lets the user nudge it into sync without
                    // re-searching, the real fix for "timing doesn't quite
                    // match the speech" (usually a fixed offset from a
                    // slightly different release/cut, not a bad file).
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Subtitle sync', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.white70, size: 20),
                              tooltip: 'Subtitles earlier',
                              onPressed: () => _adjustSubtitleDelay(-0.25, setSheetState),
                            ),
                            SizedBox(
                              width: 56,
                              child: Text(
                                '${_subtitleDelaySeconds >= 0 ? '+' : ''}${_subtitleDelaySeconds.toStringAsFixed(2)}s',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, color: Colors.white70, size: 20),
                              tooltip: 'Subtitles later',
                              onPressed: () => _adjustSubtitleDelay(0.25, setSheetState),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (_loadingExternalSubtitles)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
                    )
                  else if (_externalSubtitlesError != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Subtitle search failed:\n$_externalSubtitlesError',
                        style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
                      ),
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
                          // Previously-picked subtitles get a tinted
                          // background so it's obvious at a glance which
                          // ones have already been tried for this or any
                          // other title. The single most recent pick gets
                          // its own distinct light-yellow highlight instead,
                          // taking priority over the general tint.
                          final isLastDownloaded =
                              _lastDownloadedSubtitleId != null && sub.id == _lastDownloadedSubtitleId;
                          final isDownloaded = _downloadedSubtitleIds.contains(sub.id);
                          final highlighted = isLastDownloaded || isDownloaded;
                          return ListTile(
                            tileColor: isLastDownloaded
                                ? Colors.yellow.withOpacity(0.22)
                                : isDownloaded
                                    ? AppTheme.accent.withOpacity(0.18)
                                    : null,
                            shape: highlighted
                                ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                                : null,
                            leading: const Icon(Icons.closed_caption_outlined, color: Colors.white70),
                            title: Text(sub.displayName, style: const TextStyle(color: Colors.white)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  sub.downloadCount > 0 ? '${sub.source} - ${sub.downloadCount} downloads' : sub.source,
                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                                if (isLastDownloaded)
                                  const Text(
                                    'Last downloaded',
                                    style: TextStyle(color: Colors.yellow, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                              ],
                            ),
                            trailing: isLastDownloaded
                                ? const Icon(Icons.history, color: Colors.yellow, size: 18)
                                : isDownloaded
                                    ? const Icon(Icons.check_circle, color: AppTheme.accent, size: 18)
                                    : null,
                            onTap: () {
                              unawaited(_applyExternalSubtitle(sub));
                              Navigator.pop(sheetContext);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
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
              child: LiquidGlass(
                borderRadius: BorderRadius.circular(16),
                opacity: 0.72,
                padding: const EdgeInsets.all(16),
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
      child: LiquidGlass(
        circular: true,
        blur: 16,
        padding: const EdgeInsets.all(8),
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
