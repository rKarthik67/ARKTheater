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
import '../services/torrent_stream_service.dart';
import 'package:provider/provider.dart';

import '../state/recently_watched_provider.dart';
import '../state/settings_provider.dart';
import '../services/subtitle_download_history_service.dart';
import '../services/subtitle_style_service.dart';
import '../utils/subtitle_sync.dart';
import '../widgets/subtitle_style_sheet.dart';
import '../video_providers/common.dart';
import '../video_providers/names.dart';
import '../video_providers/provider_loader.dart';
import 'webview_player_screen.dart';

/// Android playback screen with the same better_player_plus engine and
/// feature set as [MobilePlayerScreen] (see that file for the engine
/// rationale), but with the built-in control bar switched off
/// (`showControls: false`) in favor of a custom chrome modeled on
/// ark-theater-play-web's ArkPlayer (`custom-player.js`/`styles.css`): a
/// bottom-sheet settings panel with a 2x2 Quality/Server/Subtitles/Audio
/// grid, Sleep Timer, Playback Speed, and tap-to-toggle chrome.
///
/// Opt-in via Settings > "Use new player (beta)" - see player_screen.dart.
/// Every engine-level method below (provider/quality switching, subtitle
/// fetch/sync, resume position, freeze watchdog, torrent HUD) is ported
/// unchanged from MobilePlayerScreen; only the UI that triggers them differs.
class ArkMobilePlayerScreen extends StatefulWidget {
  const ArkMobilePlayerScreen({
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
  State<ArkMobilePlayerScreen> createState() => _ArkMobilePlayerScreenState();
}

const List<double> _kSpeedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
const List<Duration?> _kSleepOptions = [
  null,
  Duration(minutes: 15),
  Duration(minutes: 30),
  Duration(minutes: 45),
  Duration(minutes: 60),
];

String _sleepLabel(Duration? option) =>
    option == null ? 'Off' : '${option.inMinutes} min';

class _ArkMobilePlayerScreenState extends State<ArkMobilePlayerScreen> {
  BetterPlayerController? _controller;
  final _playbackPosition = PlaybackPositionService();

  void _onPositionSaved(bool finished) {
    if (!finished) return;
    unawaited(context.read<RecentlyWatchedProvider>().removeItem(
          widget.mediaType,
          widget.tmdbId,
          season: widget.season,
          episode: widget.episode,
        ));
    unawaited(_subtitleDownloadHistory.clearForMedia(
      mediaType: widget.mediaType,
      tmdbId: widget.tmdbId,
      season: widget.season,
      episode: widget.episode,
    ));
  }

  late int _providerIndex;
  late ProviderLoadResult _result;
  RegularVideoLinks? _currentLink;

  bool get _isTorrentSource => (_result.videoLinks ?? const [])
      .any((link) => (link.url ?? '').startsWith('http://127.0.0.1:'));
  StreamSubscription<TorrentStreamStatus>? _torrentStatusSub;
  TorrentStreamStatus? _torrentStatus;

  bool _loading = true;
  bool _switchingProvider = false;
  String? _fatalError;

  Timer? _freezeWatchdog;
  Duration _lastKnownPosition = Duration.zero;
  DateTime _lastProgressAt = DateTime.now();
  bool _showFrozenHint = false;

  List<ExternalSubtitle> _externalSubtitles = [];
  String? _externalSubtitlesError;
  bool _fetchedExternalSubtitles = false;
  bool _loadingExternalSubtitles = false;

  double _subtitleDelaySeconds = 0.0;
  String? _activeSubtitleRawContent;
  String? _activeSubtitleName;
  final _subtitleDownloadHistory = SubtitleDownloadHistoryService();
  Set<String> _downloadedSubtitleIds = const {};
  String? _lastDownloadedSubtitleId;

  SubtitleStyle _subtitleStyle = SubtitleStyle.defaultStyle;
  SubtitleStyle _appliedSubtitleStyle = SubtitleStyle.defaultStyle;

  // New in this player (not in MobilePlayerScreen): playback speed and a
  // sleep timer, matching the ArkPlayer web settings sheet.
  double _playbackSpeed = 1.0;
  Duration? _sleepOption;
  Timer? _sleepTimer;

  // Chrome (top/bottom bars) visibility, mirroring custom-player.js's
  // showBar()/idle-hide pattern: visible on load/pause/any tap, auto-hides
  // after a few seconds of inactivity while playing.
  bool _chromeVisible = true;
  Timer? _chromeHideTimer;
  bool _showPlayPausePulse = false;
  Timer? _pulseTimer;

  @override
  void initState() {
    super.initState();
    _providerIndex = widget.initialProviderIndex;
    _result = widget.initialResult;
    WakelockPlus.enable();
    _loadSubtitleDownloadHistory();
    _initSubtitleStyleThenController();
    if (_isTorrentSource) {
      _torrentStatusSub = TorrentStreamService.statuses.listen((status) {
        if (mounted) setState(() => _torrentStatus = status);
      });
    }
    _armChromeHideTimer();
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

  void _onSubtitleStylePreviewChanged(SubtitleStyle style) {
    setState(() => _subtitleStyle = style);
    unawaited(SubtitleStyleService().save(style));
  }

  Future<void> _reloadIfStyleChanged() async {
    if (_subtitleStyle == _appliedSubtitleStyle) return;
    final resumePosition = _controller?.videoPlayerController?.value.position;
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
    _torrentStatusSub?.cancel();
    _sleepTimer?.cancel();
    _chromeHideTimer?.cancel();
    _pulseTimer?.cancel();
    WakelockPlus.disable();
    final videoValue = _controller?.videoPlayerController?.value;
    if (videoValue != null) {
      unawaited(_playbackPosition
          .save(
            mediaType: widget.mediaType,
            tmdbId: widget.tmdbId,
            season: widget.season,
            episode: widget.episode,
            position: videoValue.position,
            duration: videoValue.duration ?? Duration.zero,
          )
          .then(_onPositionSaved));
    }
    _controller?.dispose(forceDispose: true);
    super.dispose();
  }

  String _formatDuration(Duration d) {
    if (d.isNegative || d == Duration.zero) return '0:00';
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    final mm =
        hours > 0 ? minutes.toString().padLeft(2, '0') : minutes.toString();
    final ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  Color _playerAccent(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    return settings.playerAccentColor ?? settings.accentColor ?? AppTheme.accent;
  }

  void _setupController(
      {Duration? resumeAt, bool preserveActiveSubtitle = false}) {
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
        // The whole built-in control bar/overflow menu is switched off -
        // this screen draws its own chrome and settings sheet below.
        controlsConfiguration: const BetterPlayerControlsConfiguration(
          showControls: false,
        ),
        errorBuilder: (context, errorMessage) => _ArkPlaybackErrorView(
          message: errorMessage ?? 'Playback failed',
          hasOtherProviders: widget.providers.length > 1,
          onTryAnotherSource: () => _openSettingsSheet(initialPage: _SheetPage.server),
          onWatchEmbedded: _openWebViewFallback,
        ),
      ),
    );
    _controller!.addEventsListener(_onPlayerEvent);
    unawaited(_openCurrentResult(
        resumeAt: resumeAt, preserveActiveSubtitle: preserveActiveSubtitle));
  }

  BetterPlayerVideoFormat? _inferFormat(RegularVideoLinks link) {
    if (link.isM3U8 == true) return BetterPlayerVideoFormat.hls;
    if (link.isDash == true) return BetterPlayerVideoFormat.dash;
    final lower = (link.url ?? '').toLowerCase();
    if (lower.contains('.m3u8')) return BetterPlayerVideoFormat.hls;
    if (lower.contains('.mpd')) return BetterPlayerVideoFormat.dash;
    return null;
  }

  Future<void> _openCurrentResult(
      {Duration? resumeAt, bool preserveActiveSubtitle = false}) async {
    final links = _result.videoLinks ?? const [];
    if (links.isEmpty) {
      setState(() {
        _loading = false;
        _fatalError = 'No playable source for this title.';
      });
      return;
    }

    final primary = links.firstWhere(
      (link) => link.url != null && link.url == _currentLink?.url,
      orElse: () => links.first,
    );
    _currentLink = primary;
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
      bufferingConfiguration: const BetterPlayerBufferingConfiguration(
        minBufferMs: 15000,
        maxBufferMs: 30000,
        bufferForPlaybackMs: 2500,
        bufferForPlaybackAfterRebufferMs: 5000,
      ),
    );

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
      if (_playbackSpeed != 1.0) {
        unawaited(_controller!.setSpeed(_playbackSpeed));
      }

      if (preserveActiveSubtitle && _activeSubtitleRawContent != null) {
        _reapplySubtitleWithOffset();
      }

      final fromStorage = resumeAt == null;
      final target = resumeAt ??
          await _playbackPosition.load(
            mediaType: widget.mediaType,
            tmdbId: widget.tmdbId,
            season: widget.season,
            episode: widget.episode,
          );
      if (target != null && target > const Duration(seconds: 2)) {
        final sourceDuration =
            _controller?.videoPlayerController?.value.duration;
        final lastSafePosition = sourceDuration == null
            ? null
            : sourceDuration - const Duration(seconds: 5);
        if (lastSafePosition != null &&
            lastSafePosition > Duration.zero &&
            target < lastSafePosition) {
          await _controller!.seekTo(target);
          if (fromStorage && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('Resumed from ${_formatDuration(target)}')),
            );
          }
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
      return;
    }
  }

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

      unawaited(_playbackPosition
          .save(
            mediaType: widget.mediaType,
            tmdbId: widget.tmdbId,
            season: widget.season,
            episode: widget.episode,
            position: position,
            duration: videoValue?.duration ?? Duration.zero,
          )
          .then(_onPositionSaved));

      if (!isPlaying) return;

      if ((position - _lastKnownPosition).abs() > const Duration(seconds: 1)) {
        _lastKnownPosition = position;
        _lastProgressAt = DateTime.now();
        if (_showFrozenHint) setState(() => _showFrozenHint = false);
        return;
      }

      final frozenFor = DateTime.now().difference(_lastProgressAt);
      if (frozenFor > const Duration(seconds: 50) && !_showFrozenHint) {
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
        SnackBar(
            content: Text(
                '${provider.displayName} has no playable source right now.')),
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

  void _switchQuality(RegularVideoLinks link) {
    if (link.url == null || link.url == _currentLink?.url) return;
    final resumePosition = _controller?.videoPlayerController?.value.position;
    setState(() => _currentLink = link);
    unawaited(_openCurrentResult(resumeAt: resumePosition));
  }

  void _setPlaybackSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
    unawaited(_controller?.setSpeed(speed));
  }

  void _setSleepOption(Duration? option) {
    _sleepTimer?.cancel();
    setState(() => _sleepOption = option);
    if (option == null) return;
    _sleepTimer = Timer(option, () {
      unawaited(_controller?.pause());
    });
  }

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

  void _adjustSubtitleDelay(
      double deltaSeconds, void Function(void Function()) setSheetState) {
    if (_activeSubtitleRawContent == null) return;
    _subtitleDelaySeconds =
        (_subtitleDelaySeconds + deltaSeconds).clamp(-30.0, 30.0);
    _reapplySubtitleWithOffset();
    setSheetState(() {});
  }

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
      final response = await http
          .get(Uri.parse(sub.url))
          .timeout(const Duration(seconds: 15));
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

  Future<void> _fetchExternalSubtitles(
      void Function(void Function()) setSheetState) async {
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
      _externalSubtitlesError = error.toString();
    } finally {
      _fetchedExternalSubtitles = true;
      _loadingExternalSubtitles = false;
      setSheetState(() {});
    }
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

  Future<void> _handleBack() async {
    try {
      await _controller?.pause();
    } catch (_) {
      // Best-effort - still proceed to pop even if pause failed/raced.
    }
    if (mounted) Navigator.of(context).pop();
  }

  // --- Chrome visibility -----------------------------------------------

  void _armChromeHideTimer() {
    _chromeHideTimer?.cancel();
    _chromeHideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      final isPlaying = _controller?.isPlaying() ?? false;
      if (isPlaying) setState(() => _chromeVisible = false);
    });
  }

  void _showChrome() {
    setState(() => _chromeVisible = true);
    _armChromeHideTimer();
  }

  void _toggleChrome() {
    if (_chromeVisible) {
      setState(() => _chromeVisible = false);
      _chromeHideTimer?.cancel();
    } else {
      _showChrome();
    }
  }

  void _togglePlayPause() {
    final isPlaying = _controller?.isPlaying() ?? false;
    if (isPlaying) {
      unawaited(_controller?.pause());
    } else {
      unawaited(_controller?.play());
    }
    _pulseTimer?.cancel();
    setState(() => _showPlayPausePulse = true);
    _pulseTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _showPlayPausePulse = false);
    });
    _showChrome();
  }

  void _seekBy(Duration delta) {
    final controller = _controller;
    final value = controller?.videoPlayerController?.value;
    if (controller == null || value == null) return;
    final duration = value.duration ?? Duration.zero;
    var target = value.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    unawaited(controller.seekTo(target));
    _showChrome();
  }

  // --- Settings sheet -----------------------------------------------------

  void _openSettingsSheet({_SheetPage initialPage = _SheetPage.main}) {
    _showChrome();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _ArkSettingsSheet(
        initialPage: initialPage,
        state: this,
      ),
    ).then((_) => _reloadIfStyleChanged());
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
                _ArkPlaybackErrorView(
                  message: _fatalError!,
                  hasOtherProviders: widget.providers.length > 1,
                  onTryAnotherSource: () =>
                      _openSettingsSheet(initialPage: _SheetPage.server),
                  onWatchEmbedded: _openWebViewFallback,
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: _ArkCircleIconButton(
                      icon: Icons.arrow_back, onTap: _handleBack),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final controller = _controller;
    final videoValue = controller?.videoPlayerController?.value;

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
            if (controller != null) BetterPlayer(controller: controller),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleChrome,
                onDoubleTapDown: (details) {
                  final width = MediaQuery.sizeOf(context).width;
                  if (details.globalPosition.dx < width / 2) {
                    _seekBy(const Duration(seconds: -10));
                  } else {
                    _seekBy(const Duration(seconds: 10));
                  }
                },
              ),
            ),
            if (_showPlayPausePulse)
              Center(
                child: _ArkPulseIcon(
                  icon: (controller?.isPlaying() ?? false)
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                ),
              ),
            AnimatedOpacity(
              opacity: _chromeVisible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !_chromeVisible,
                child: _ArkChrome(
                  title: widget.title,
                  videoValue: videoValue,
                  accent: _playerAccent(context),
                  onBack: _handleBack,
                  onTogglePlayPause: _togglePlayPause,
                  onSeekBack: () => _seekBy(const Duration(seconds: -10)),
                  onSeekForward: () => _seekBy(const Duration(seconds: 10)),
                  onScrub: (position) {
                    unawaited(controller?.seekTo(position));
                    _showChrome();
                  },
                  onOpenSettings: () => _openSettingsSheet(),
                  formatDuration: _formatDuration,
                ),
              ),
            ),
            if (_torrentStatus != null)
              Positioned(
                top: 8,
                right: 8,
                child: SafeArea(
                  child: _ArkPill(label: _torrentStatus!.label),
                ),
              ),
            if (_loading || _switchingProvider)
              Center(
                  child: CircularProgressIndicator(color: _playerAccent(context))),
            if (_showFrozenHint && !_loading)
              Positioned(
                left: 24,
                right: 24,
                bottom: 120,
                child: _ArkFrozenHint(
                  hasOtherProviders: widget.providers.length > 1,
                  onTryAnotherSource: () =>
                      _openSettingsSheet(initialPage: _SheetPage.server),
                  onWatchEmbedded: _openWebViewFallback,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _SheetPage { main, quality, server, subtitles, audio, sleep, speed }

/// The ArkPlayer-styled bottom sheet: a 2x2 Quality/Server/Subtitles/Audio
/// grid plus Sleep Timer/Playback Speed/Subtitle Settings rows on the main
/// page, each grid card drilling into its own sub-page with a back-chevron
/// header - mirroring custom-player.js's showXSub()/backToMain() pattern.
class _ArkSettingsSheet extends StatefulWidget {
  const _ArkSettingsSheet({required this.initialPage, required this.state});

  final _SheetPage initialPage;
  final _ArkMobilePlayerScreenState state;

  @override
  State<_ArkSettingsSheet> createState() => _ArkSettingsSheetState();
}

class _ArkSettingsSheetState extends State<_ArkSettingsSheet> {
  late _SheetPage _page = widget.initialPage;

  _ArkMobilePlayerScreenState get s => widget.state;

  @override
  void initState() {
    super.initState();
    if (_page == _SheetPage.subtitles && !s._fetchedExternalSubtitles) {
      s._loadingExternalSubtitles = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        s._fetchExternalSubtitles(setState);
      });
    }
  }

  void _goTo(_SheetPage page) => setState(() => _page = page);

  @override
  Widget build(BuildContext context) {
    final accent = s._playerAccent(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (sheetContext, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xF0171717),
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                child: Row(
                  children: [
                    if (_page != _SheetPage.main)
                      IconButton(
                        icon: const Icon(Icons.chevron_left, color: Colors.white),
                        onPressed: () => _goTo(_SheetPage.main),
                      )
                    else
                      const SizedBox(width: 48),
                    Expanded(
                      child: Text(
                        _titleFor(_page),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  children: [_buildPage(accent)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _titleFor(_SheetPage page) => switch (page) {
        _SheetPage.main => 'Settings',
        _SheetPage.quality => 'Quality',
        _SheetPage.server => 'Server',
        _SheetPage.subtitles => 'Subtitles',
        _SheetPage.audio => 'Audio',
        _SheetPage.sleep => 'Sleep Timer',
        _SheetPage.speed => 'Playback Speed',
      };

  Widget _buildPage(Color accent) {
    switch (_page) {
      case _SheetPage.main:
        return _buildMain(accent);
      case _SheetPage.quality:
        return _buildQuality(accent);
      case _SheetPage.server:
        return _buildServer(accent);
      case _SheetPage.subtitles:
        return _buildSubtitles(accent);
      case _SheetPage.audio:
        return _buildAudio(accent);
      case _SheetPage.sleep:
        return _buildSleep(accent);
      case _SheetPage.speed:
        return _buildSpeed(accent);
    }
  }

  Widget _buildMain(Color accent) {
    final links = s._result.videoLinks ?? const [];
    final qualityCount = links.map((l) => l.quality ?? 'auto').toSet().length;
    final audioCount = audioLabelsForLinks(links).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.7,
          children: [
            _ArkSheetCard(
              icon: Icons.high_quality_outlined,
              label: 'Quality',
              value: s._currentLink?.quality ?? 'Auto',
              enabled: qualityCount > 1,
              onTap: () => _goTo(_SheetPage.quality),
            ),
            _ArkSheetCard(
              icon: Icons.dns_outlined,
              label: 'Server',
              value: s.widget.providers.isNotEmpty
                  ? s.widget.providers[s._providerIndex].displayName
                  : '-',
              enabled: s.widget.providers.length > 1,
              onTap: () => _goTo(_SheetPage.server),
            ),
            _ArkSheetCard(
              icon: Icons.subtitles_outlined,
              label: 'Subtitles',
              value: s._activeSubtitleName ?? 'Off',
              enabled: true,
              onTap: () => _goTo(_SheetPage.subtitles),
            ),
            _ArkSheetCard(
              icon: Icons.headphones_outlined,
              label: 'Audio',
              value: s._currentLink != null
                  ? audioLabelForLink(s._currentLink!)
                  : 'Default',
              enabled: audioCount > 1,
              onTap: () => _goTo(_SheetPage.audio),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ArkSheetRow(
          icon: Icons.bedtime_outlined,
          label: 'Sleep Timer',
          value: _sleepLabel(s._sleepOption),
          onTap: () => _goTo(_SheetPage.sleep),
        ),
        _ArkSheetRow(
          icon: Icons.speed_outlined,
          label: 'Playback Speed',
          value: '${s._playbackSpeed}x',
          onTap: () => _goTo(_SheetPage.speed),
        ),
        _ArkSheetRow(
          icon: Icons.format_color_text_outlined,
          label: 'Subtitle Settings',
          value: '',
          onTap: () {
            Navigator.of(context).pop();
            s._showSubtitleStyleSheet();
          },
        ),
      ],
    );
  }

  Widget _buildQuality(Color accent) {
    final links = s._result.videoLinks ?? const [];
    final seen = <String>{};
    final unique = <RegularVideoLinks>[];
    for (final link in links) {
      final key = link.quality ?? 'auto';
      if (seen.add(key)) unique.add(link);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final link in unique)
          _ArkRadioTile(
            label: link.quality ?? 'Auto',
            selected: link.url == s._currentLink?.url ||
                link.quality == s._currentLink?.quality,
            accent: accent,
            onTap: () {
              Navigator.of(context).pop();
              s._switchQuality(link);
            },
          ),
      ],
    );
  }

  Widget _buildServer(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < s.widget.providers.length; i++)
          _ArkRadioTile(
            label: s.widget.providers[i].displayName,
            selected: i == s._providerIndex,
            accent: accent,
            onTap: () {
              Navigator.of(context).pop();
              unawaited(s._switchProvider(i));
            },
          ),
      ],
    );
  }

  Widget _buildAudio(Color accent) {
    final links = s._result.videoLinks ?? const [];
    final labels = audioLabelsForLinks(links);
    final current = s._currentLink ?? (links.isEmpty ? null : links.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final label in labels)
          _ArkRadioTile(
            label: label,
            selected: current != null && audioLabelForLink(current) == label,
            accent: accent,
            onTap: () {
              final sameQuality = links.where((link) =>
                  audioLabelForLink(link) == label &&
                  link.quality == current?.quality);
              final next = sameQuality.isNotEmpty
                  ? sameQuality.first
                  : links.firstWhere((link) => audioLabelForLink(link) == label);
              Navigator.of(context).pop();
              s._switchQuality(next);
            },
          ),
      ],
    );
  }

  Widget _buildSleep(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final option in _kSleepOptions)
          _ArkRadioTile(
            label: _sleepLabel(option),
            selected: option == s._sleepOption,
            accent: accent,
            onTap: () {
              s._setSleepOption(option);
              _goTo(_SheetPage.main);
            },
          ),
      ],
    );
  }

  Widget _buildSpeed(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final speed in _kSpeedOptions)
          _ArkRadioTile(
            label: speed == 1.0 ? 'Normal' : '${speed}x',
            selected: speed == s._playbackSpeed,
            accent: accent,
            onTap: () {
              s._setPlaybackSpeed(speed);
              _goTo(_SheetPage.main);
            },
          ),
      ],
    );
  }

  Widget _buildSubtitles(Color accent) {
    final subtitles = s._result.subtitleLinks ?? const <RegularSubtitleLinks>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Text('From this source',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ),
        _ArkRadioTile(
          label: 'Off',
          selected: s._activeSubtitleName == null,
          accent: accent,
          onTap: () {
            s._subtitleDelaySeconds = 0.0;
            s._activeSubtitleRawContent = null;
            s._activeSubtitleName = null;
            s._controller?.setupSubtitleSource(
              BetterPlayerSubtitlesSource(
                  type: BetterPlayerSubtitlesSourceType.none),
            );
            setState(() {});
          },
        ),
        for (final subtitle in subtitles)
          if (subtitle.url != null)
            _ArkRadioTile(
              label: subtitle.language ?? 'Unknown',
              selected: s._activeSubtitleName == subtitle.language &&
                  s._activeSubtitleRawContent == null,
              accent: accent,
              onTap: () {
                s._subtitleDelaySeconds = 0.0;
                s._activeSubtitleRawContent = null;
                s._activeSubtitleName = subtitle.language;
                s._controller?.setupSubtitleSource(
                  BetterPlayerSubtitlesSource(
                    type: BetterPlayerSubtitlesSourceType.network,
                    urls: [subtitle.url!],
                    name: subtitle.language ?? 'Unknown',
                    headers: subtitle.headers,
                  ),
                );
                setState(() {});
              },
            ),
        const Divider(color: Colors.white24, height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Search subtitles',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showExternalSubtitleSearch();
              },
              child: Text('Search', style: TextStyle(color: accent)),
            ),
          ],
        ),
        if (s._activeSubtitleRawContent != null) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Subtitle sync',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: Colors.white70, size: 20),
                    onPressed: () => s._adjustSubtitleDelay(-0.25, setState),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      '${s._subtitleDelaySeconds >= 0 ? '+' : ''}${s._subtitleDelaySeconds.toStringAsFixed(2)}s',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline,
                        color: Colors.white70, size: 20),
                    onPressed: () => s._adjustSubtitleDelay(0.25, setState),
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }

  // The external subtitle search list is left as its own sheet (pushed on
  // top) rather than folded into the grid sub-page - it has its own
  // loading/error/list states that don't fit the plain radio-tile layout
  // the other sub-pages share.
  void _showExternalSubtitleSearch() {
    var sheetOpen = true;
    showModalBottomSheet<void>(
      context: s.context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          if (!s._fetchedExternalSubtitles && !s._loadingExternalSubtitles) {
            s._loadingExternalSubtitles = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (sheetOpen) s._fetchExternalSubtitles(setSheetState);
            });
          }
          final sheetHeight = MediaQuery.sizeOf(sheetContext).height * 0.72;
          final accent = s._playerAccent(sheetContext);
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xF0171717),
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: SafeArea(
              child: SizedBox(
                height: sheetHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Search subtitles',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      if (s._loadingExternalSubtitles)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child:
                              Center(child: CircularProgressIndicator(color: accent)),
                        )
                      else if (s._externalSubtitlesError != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Subtitle search failed:\n${s._externalSubtitlesError}',
                            style: const TextStyle(
                                color: Colors.orangeAccent, fontSize: 13),
                          ),
                        )
                      else if (s._externalSubtitles.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                              'No external subtitles found for this title.',
                              style: TextStyle(color: Colors.white54)),
                        )
                      else
                        Expanded(
                          child: ListView.builder(
                            itemCount: s._externalSubtitles.length,
                            itemBuilder: (context, index) {
                              final sub = s._externalSubtitles[index];
                              final isLastDownloaded =
                                  s._lastDownloadedSubtitleId != null &&
                                      sub.id == s._lastDownloadedSubtitleId;
                              final isDownloaded =
                                  s._downloadedSubtitleIds.contains(sub.id);
                              return ListTile(
                                tileColor: isLastDownloaded
                                    ? Colors.yellow.withOpacity(0.22)
                                    : isDownloaded
                                        ? accent.withOpacity(0.18)
                                        : null,
                                leading: const Icon(Icons.closed_caption_outlined,
                                    color: Colors.white70),
                                title: Text(sub.displayName,
                                    style: const TextStyle(color: Colors.white)),
                                subtitle: Text(
                                  sub.downloadCount > 0
                                      ? '${sub.source} - ${sub.downloadCount} downloads'
                                      : sub.source,
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 11),
                                ),
                                onTap: () {
                                  unawaited(s._applyExternalSubtitle(sub));
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
            ),
          );
        },
      ),
    ).whenComplete(() => sheetOpen = false);
  }
}

// --- Small presentational widgets, styled after ark-theater-play-web's
// .ark-sheet / .ark-sheet-card / .ark-row CSS (a flat, near-opaque dark
// surface, deliberately distinct from the rest of the app's LiquidGlass
// look since this is meant to match the web ArkPlayer specifically). ---

class _ArkSheetCard extends StatelessWidget {
  const _ArkSheetCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white70, size: 20),
                const SizedBox(height: 6),
                Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArkSheetRow extends StatelessWidget {
  const _ArkSheetRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Colors.white70),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value.isNotEmpty)
            Text(value, style: const TextStyle(color: Colors.white54)),
          const Icon(Icons.chevron_right, color: Colors.white38),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _ArkRadioTile extends StatelessWidget {
  const _ArkRadioTile({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? accent : Colors.white54,
      ),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }
}

class _ArkChrome extends StatelessWidget {
  const _ArkChrome({
    required this.title,
    required this.videoValue,
    required this.accent,
    required this.onBack,
    required this.onTogglePlayPause,
    required this.onSeekBack,
    required this.onSeekForward,
    required this.onScrub,
    required this.onOpenSettings,
    required this.formatDuration,
  });

  final String title;
  final VideoPlayerValue? videoValue;
  final Color accent;
  final VoidCallback onBack;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekForward;
  final ValueChanged<Duration> onScrub;
  final VoidCallback onOpenSettings;
  final String Function(Duration) formatDuration;

  @override
  Widget build(BuildContext context) {
    final position = videoValue?.position ?? Duration.zero;
    final duration = videoValue?.duration ?? Duration.zero;
    final isPlaying = videoValue?.isPlaying ?? false;
    final sliderMax = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final sliderValue =
        position.inMilliseconds.toDouble().clamp(0, sliderMax);

    return Stack(
      children: [
        // Top gradient scrim + back button/title.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xCC000000), Colors.transparent],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  _ArkCircleIconButton(icon: Icons.arrow_back, onTap: onBack),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Bottom gradient scrim + transport + scrub bar.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xCC000000), Colors.transparent],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.replay_10_rounded,
                            color: Colors.white, size: 28),
                        onPressed: onSeekBack,
                      ),
                      const SizedBox(width: 12),
                      _ArkCircleIconButton(
                        icon: isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        onTap: onTogglePlayPause,
                        size: 52,
                        iconSize: 30,
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.forward_10_rounded,
                            color: Colors.white, size: 28),
                        onPressed: onSeekForward,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: Text(formatDuration(position),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            activeTrackColor: accent,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: accent,
                            overlayShape: SliderComponentShape.noOverlay,
                            thumbShape:
                                const RoundSliderThumbShape(enabledThumbRadius: 6),
                          ),
                          child: Slider(
                            value: sliderValue.toDouble(),
                            min: 0,
                            max: sliderMax,
                            onChanged: (value) =>
                                onScrub(Duration(milliseconds: value.round())),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(formatDuration(duration),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings_outlined,
                            color: Colors.white),
                        onPressed: onOpenSettings,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ArkCircleIconButton extends StatelessWidget {
  const _ArkCircleIconButton({
    required this.icon,
    required this.onTap,
    this.size = 40,
    this.iconSize = 22,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(size / 2),
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: iconSize),
      ),
    );
  }
}

class _ArkPulseIcon extends StatelessWidget {
  const _ArkPulseIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 40),
    );
  }
}

class _ArkPill extends StatelessWidget {
  const _ArkPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.hub_outlined, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}

class _ArkFrozenHint extends StatelessWidget {
  const _ArkFrozenHint({
    required this.hasOtherProviders,
    required this.onTryAnotherSource,
    required this.onWatchEmbedded,
  });

  final bool hasOtherProviders;
  final VoidCallback onTryAnotherSource;
  final VoidCallback onWatchEmbedded;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.72),
        borderRadius: BorderRadius.circular(16),
      ),
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
              if (hasOtherProviders)
                ElevatedButton(
                  onPressed: onTryAnotherSource,
                  child: const Text('Try another source'),
                ),
              OutlinedButton(
                onPressed: onWatchEmbedded,
                child: const Text('Watch via embedded player'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArkPlaybackErrorView extends StatelessWidget {
  const _ArkPlaybackErrorView({
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
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (hasOtherProviders)
                  ElevatedButton(
                      onPressed: onTryAnotherSource,
                      child: const Text('Try another source')),
                OutlinedButton(
                    onPressed: onWatchEmbedded,
                    child: const Text('Watch via embedded player')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
