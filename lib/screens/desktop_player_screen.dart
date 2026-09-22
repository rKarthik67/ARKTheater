import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../models/media_item.dart';
import '../models/external_subtitle.dart';
import '../services/external_subtitle_service.dart';
import '../services/playback_position_service.dart';
import 'package:provider/provider.dart';

import '../state/recently_watched_provider.dart';
import '../services/subtitle_download_history_service.dart';
import '../services/subtitle_style_service.dart';
import '../video_providers/common.dart';
import '../widgets/subtitle_style_sheet.dart';
import '../widgets/liquid_glass.dart';
import '../video_providers/names.dart';
import '../video_providers/provider_loader.dart';
import 'webview_player_screen.dart';

/// Native, ad-free playback screen. Every `RegularVideoLinks` this screen
/// ever opens came straight from ARKVideoScrapper (or the direct VixSrc
/// fallback) - there is no iframe, no provider webpage, and no ad script
/// anywhere in this widget tree.
///
/// Providers are resolved lazily here: DetailScreen only resolves the one
/// that won the initial race (see ProviderLoader.loadFirstSuccessful);
/// switching servers from the menu below resolves on demand, the same way
/// flixquest's player lazily loads a provider only once it's selected.
class DesktopPlayerScreen extends StatefulWidget {
  const DesktopPlayerScreen({
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
  State<DesktopPlayerScreen> createState() => _DesktopPlayerScreenState();
}

class _DesktopPlayerScreenState extends State<DesktopPlayerScreen> {
  final _playbackPosition = PlaybackPositionService();

  // Once a title/episode is fully watched, PlaybackPositionService.save()
  // clears its resume spot and reports it as finished - at that point it
  // no longer belongs in "Recently Watched" either, since there's nothing
  // left to continue.
  void _onPositionSaved(bool finished) {
    if (!finished) return;
    unawaited(context.read<RecentlyWatchedProvider>().removeItem(
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
  late final Player _player;
  late final VideoController _controller;

  late int _providerIndex;
  late ProviderLoadResult _result;
  late RegularVideoLinks _currentLink;

  bool _loading = true;
  bool _buffering = true;
  bool _switchingProvider = false;
  String? _error;
  double _speed = 1.0;
  Timer? _stuckTimer;
  bool _showStuckHint = false;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;
  Duration _lastProgressPosition = Duration.zero;
  Timer? _positionSaveTimer;
  Timer? _gestureLabelTimer;
  static const _displayChannel = MethodChannel('ark_theater/display');
  bool _controlsVisible = true;
  double _brightness = 0.5;
  String? _gestureLabel;

  // Drives the custom seek bar - the default media_kit controls are turned
  // off (see `controls: NoVideoControls` below) because their built-in
  // seek bar sits flush with the bottom edge, where it fights the system
  // back-gesture/nav-bar swipe area for drag gestures. This one is drawn
  // with real breathing room above the edge instead.
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = true;
  bool _seeking = false;
  bool _confirmingSeek = false;

  // Subtitles fetched directly from Wyzie Subs by TMDB id/season/episode -
  // independent of whichever provider is currently playing, ported from
  // flixquest's ExternalSubtitleService/PlayerExternalSubtitles. Cached at
  // this level (not per sheet-open) so reopening the sheet doesn't refetch.
  List<ExternalSubtitle> _externalSubtitles = [];
  String? _externalSubtitlesError;
  bool _fetchedExternalSubtitles = false;
  bool _loadingExternalSubtitles = false;

  // Manual subtitle sync offset (seconds) - the real fix for the common
  // "subtitle timing doesn't quite match the speech" complaint, which is
  // usually just a fixed global offset (the subtitle file was made for a
  // slightly different release/cut of the video), not random per-line
  // drift. mpv's native `sub-delay` property applies this instantly without
  // needing to re-parse the subtitle file ourselves. Positive = subtitles
  // appear later (delayed), negative = subtitles appear earlier (advanced) -
  // same convention as mpv's own z/x keyboard shortcuts. Reset to 0 whenever
  // a new video loads (see _loadCurrentLink) so an offset dialed in for one
  // title/episode doesn't silently carry over into the next.
  double _subtitleDelaySeconds = 0.0;
  final _subtitleDownloadHistory = SubtitleDownloadHistoryService();
  Set<String> _downloadedSubtitleIds = const {};
  // The single most recently picked subtitle - gets its own distinct
  // highlight (light yellow + "Last downloaded" label) in the picker,
  // separate from every other past pick's plain "already tried" tint.
  String? _lastDownloadedSubtitleId;

  // User-customizable subtitle text color/background/font size. Unlike
  // mobile, mpv/media_kit needs no controller rebuild to apply a change -
  // SubtitleViewConfiguration is just read fresh on every build(), so this
  // takes effect live the instant the state changes.
  SubtitleStyle _subtitleStyle = SubtitleStyle.defaultStyle;

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

  Future<void> _loadSubtitleStyle() async {
    final style = await SubtitleStyleService().load();
    if (mounted) setState(() => _subtitleStyle = style);
  }

  void _onSubtitleStyleChanged(SubtitleStyle style) {
    setState(() => _subtitleStyle = style);
    unawaited(SubtitleStyleService().save(style));
  }

  void _showSubtitleStyleSheet() {
    showSubtitleStyleSheet(
      context: context,
      current: _subtitleStyle,
      onChanged: _onSubtitleStyleChanged,
    );
  }

  @override
  void initState() {
    super.initState();
    _providerIndex = widget.initialProviderIndex;
    _result = widget.initialResult;
    _currentLink = _result.videoLinks!.first;
    _loadSubtitleDownloadHistory();
    _loadSubtitleStyle();
    unawaited(_loadBrightness());
    _player = Player(
      configuration: const PlayerConfiguration(bufferSize: 64 * 1024 * 1024),
    );
    // Scraped sources are proxied through third-party CDNs that are often
    // slow or flaky to reconnect to after a seek. These are standard
    // libmpv/ffmpeg network-resilience tuning knobs (not app-specific) -
    // longer read-ahead cache, a bounded reconnect window instead of
    // hanging forever, and automatic reconnect on a dropped connection.
    final nativePlayer = _player.platform;
    if (nativePlayer is NativePlayer) {
      unawaited(nativePlayer.setProperty('cache', 'yes'));
      unawaited(nativePlayer.setProperty('cache-secs', '60'));
      unawaited(nativePlayer.setProperty('demuxer-max-bytes', '96MiB'));
      unawaited(nativePlayer.setProperty('demuxer-max-back-bytes', '32MiB'));
      unawaited(nativePlayer.setProperty('network-timeout', '20'));
      // Lets mpv seek within its own cache instead of purely trusting the
      // CDN's handling of HTTP Range requests when you jump to a spot that
      // isn't buffered yet - some of the scraped sources ignore or mishandle
      // Range headers, which is what makes far seeks hang on desktop even
      // though AVPlayer/ExoPlayer paper over the same behavior on iOS/Android.
      unawaited(nativePlayer.setProperty('demuxer-seekable-cache', 'yes'));
      unawaited(nativePlayer.setProperty(
        'stream-lavf-o',
        'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=5',
      ));
    }
    _controller = VideoController(_player);
    WakelockPlus.enable();

    _errorSub = _player.stream.error.listen((message) {
      if (!mounted) return;
      setState(() => _error = 'Playback error: $message');
    });
    _bufferingSub = _player.stream.buffering.listen((buffering) {
      if (!mounted) return;
      setState(() => _buffering = buffering);
    });
    _positionSub = _player.stream.position.listen((position) {
      if (!mounted) return;
      if (position > _lastProgressPosition + const Duration(milliseconds: 500)) {
        _lastProgressPosition = position;
        if (_showStuckHint) setState(() => _showStuckHint = false);
      }
      debugPrint('[ARKseek] positionStream -> $position (seeking=$_seeking playing=${_player.state.playing})');
      // Don't fight the user's finger while they're actively dragging the
      // seek bar - the stream keeps emitting the pre-seek position for a
      // moment, which would otherwise snap the thumb back mid-drag.
      if (!_seeking) setState(() => _position = position);
    });
    _durationSub = _player.stream.duration.listen((duration) {
      if (!mounted) return;
      setState(() => _duration = duration);
    });
    _playingSub = _player.stream.playing.listen((playing) {
      debugPrint('[ARKseek] playingStream -> $playing at position=${_player.state.position}');
      if (!mounted) return;
      setState(() => _playing = playing);
    });

    // Saved every few seconds regardless of play/pause state, using
    // whatever the stream listeners above last recorded into _position/
    // _duration, so pausing (or backgrounding the window) doesn't lose
    // recent progress.
    _positionSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      unawaited(_playbackPosition.save(
        mediaType: widget.mediaType,
        tmdbId: widget.tmdbId,
        season: widget.season,
        episode: widget.episode,
        position: _position,
        duration: _duration,
      ).then(_onPositionSaved));
    });

    _loadCurrentLink();
  }

  Future<void> _loadBrightness() async {
    try {
      final value = await _displayChannel.invokeMethod<double>('getBrightness');
      if (mounted && value != null) {
        setState(() => _brightness = value.clamp(0.0, 1.0).toDouble());
      }
    } catch (_) {
      // Brightness is an iOS-only enhancement; playback still works elsewhere.
    }
  }

  void _toggleControls() => setState(() => _controlsVisible = !_controlsVisible);

  void _showGestureLabel(String value) {
    _gestureLabelTimer?.cancel();
    setState(() => _gestureLabel = value);
    _gestureLabelTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _gestureLabel = null);
    });
  }

  void _adjustVerticalControl(DragUpdateDetails details, double width, double height) {
    final delta = -details.delta.dy / height;
    if (details.localPosition.dx < width / 2) {
      _brightness = (_brightness + delta).clamp(0.0, 1.0).toDouble();
      unawaited(_displayChannel.invokeMethod<void>('setBrightness', _brightness));
      _showGestureLabel('Brightness ${(_brightness * 100).round()}%');
    } else {
      final volume =
          (_player.state.volume + delta * 100).clamp(0.0, 100.0).toDouble();
      unawaited(_player.setVolume(volume));
      _showGestureLabel('Volume ${volume.round()}%');
    }
  }

  Future<void> _loadCurrentLink({Duration? resumeAt}) async {
    _stuckTimer?.cancel();
    _lastProgressPosition = Duration.zero;
    setState(() {
      _loading = true;
      _buffering = true;
      _error = null;
      _showStuckHint = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      _seeking = false;
    });
    try {
      await _player.open(Media(_currentLink.url!, httpHeaders: _currentLink.headers));
      await _player.setRate(_speed);
      _subtitleDelaySeconds = 0.0;
      final freshNativePlayer = _player.platform;
      if (freshNativePlayer is NativePlayer) {
        unawaited(freshNativePlayer.setProperty('sub-delay', '0'));
      }
      final subs = _result.subtitleLinks ?? const [];
      if (subs.isNotEmpty) {
        final first = subs.first;
        await _player.setSubtitleTrack(SubtitleTrack.uri(first.url!, title: first.language));
      }

      // Resume where playback left off: either the position carried over
      // from a provider/quality switch (resumeAt, so switching mid-title
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

      // On iOS libmpv may accept a seek while its network demuxer is still
      // opening, then apply the stream's initial 0:00 position afterwards.
      // Start playback first, give the first media packet a moment to land,
      // then use the same verified/retrying seek path as the timeline.
      await _player.play();
      _armStuckTimer();
      if (target != null && target > const Duration(seconds: 2)) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        _watchSeek(target);
        if (fromStorage && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Resumed from ${_formatDuration(target)}')),
          );
        }
      }
    } catch (err) {
      if (mounted) setState(() => _error = 'Playback failed: $err');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Checks that playback actually started at all after opening a stream -
  // used only on initial load/quality/provider switch, where "stuck" means
  // "never moved past 0".
  void _armStuckTimer() {
    _stuckTimer?.cancel();
    final referencePosition = _player.state.position;
    _stuckTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      if (_player.state.position <= referencePosition + const Duration(milliseconds: 500)) {
        setState(() => _showStuckHint = true);
      }
    });
  }

  // Watches a seek/skip actually land. This is deliberately NOT "did the
  // position move at all" (that's what _armStuckTimer checks for the
  // initial load) - a seek can "fail" in three different ways depending on
  // how the scraped CDN mishandles the Range request: it hangs forever, it
  // resets playback to 0:00, or it just silently keeps playing from
  // wherever it already was before the drag. All three look identical from
  // here: position ends up far from where we told it to go. So: check
  // against the actual target, and give it two retries (a dropped Range
  // request on the first attempt often succeeds on a second try) before
  // giving up and surfacing the "try another source" hint.
  void _watchSeek(Duration target) {
    _stuckTimer?.cancel();
    var attempt = 0;
    debugPrint('[ARKseek] start target=$target currentBefore=${_player.state.position}');
    // Deliberately NOT pausing before seeking here - pausing this kind of
    // network stream before a seek was found to leave mpv's demuxer/decode
    // pipeline stalled: state.playing flips back to true after _player.play()
    // but no further frames/position updates ever arrive. Seeking while still
    // playing is what actually works reliably against these CDNs; we just
    // hide the transient wrong-position blip in the UI instead (freeze the
    // displayed position/show the spinner via _seeking/_confirmingSeek)
    // rather than touching play/pause state at all.
    setState(() {
      _seeking = true;
      _confirmingSeek = true;
      _position = target;
    });
    _player.seek(target);

    void finish({required bool landed}) {
      debugPrint('[ARKseek] finish landed=$landed target=$target '
          'finalPosition=${_player.state.position} attempts=$attempt');
      if (!mounted) return;
      setState(() {
        _seeking = false;
        // A failed seek must always release the seek overlay. Leaving this
        // true made the yellow loading indicator permanent after a CDN
        // ignored a Range request and restarted at 0:00.
        _confirmingSeek = false;
        if (landed) {
          _showStuckHint = false;
        } else {
          // Do not leave the timeline at the requested-but-never-decoded
          // position. Once the next position event arrives it will keep this
          // value current as usual.
          _position = _player.state.position;
          _showStuckHint = true;
        }
      });
    }

    // A plain re-seek is a no-op against a connection that is already
    // wedged - it just tells the same stuck demuxer to seek to the same
    // place again. Confirmed by logging: the buffered-ahead duration read
    // back bit-for-bit identical across repeated seek retries, meaning zero
    // new bytes arrived the whole time. So retries here throw the stream
    // away and reopen it fresh instead, which gets a brand new connection
    // rather than banging on the same dead one.
    Future<void> reopenAndSeek() async {
      debugPrint('[ARKseek] reopening stream fresh for target=$target');
      try {
        await _player.open(
          Media(_currentLink.url!, httpHeaders: _currentLink.headers),
          play: true,
        );
        await _player.seek(target);
      } catch (e) {
        debugPrint('[ARKseek] reopen threw: $e');
      }
    }

    void check() {
      if (!mounted) return;
      final current = _player.state.position;
      final positionOk = (current - target).abs() <= const Duration(seconds: 6);
      // mpv reports the seek target as the "position" the instant the seek
      // command is accepted - well before any data for that byte range has
      // actually arrived. So position alone is not proof the seek landed:
      // if the CDN never delivers that range, mpv sits in $_buffering=true
      // forever while position already (falsely) says we're there. Only
      // count it as landed once we're on target AND actually decoding again.
      final onTarget = positionOk && !_buffering;
      debugPrint('[ARKseek] check attempt=$attempt target=$target current=$current '
          'positionOk=$positionOk buffering=$_buffering onTarget=$onTarget '
          'playing=${_player.state.playing} playerBuffer=${_player.state.buffer}');
      if (onTarget) {
        finish(landed: true);
        return;
      }
      attempt++;
      if (attempt <= 2) {
        unawaited(reopenAndSeek());
        _stuckTimer = Timer(const Duration(seconds: 6), check);
      } else {
        finish(landed: false);
      }
    }

    _stuckTimer = Timer(const Duration(seconds: 6), check);
  }

  @override
  void dispose() {
    _gestureLabelTimer?.cancel();
    _stuckTimer?.cancel();
    _positionSaveTimer?.cancel();
    _errorSub?.cancel();
    _bufferingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    WakelockPlus.disable();
    // Best-effort final save so closing right after the last periodic tick
    // doesn't lose up to 5 seconds of progress.
    unawaited(_playbackPosition.save(
      mediaType: widget.mediaType,
      tmdbId: widget.tmdbId,
      season: widget.season,
      episode: widget.episode,
      position: _player.state.position,
      duration: _player.state.duration,
    ).then(_onPositionSaved));
    _player.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_playing) {
      _player.pause();
    } else {
      _player.play();
    }
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

  void _switchQuality(RegularVideoLinks link) {
    if (link.url == _currentLink.url) return;
    final resumePosition = _player.state.position;
    setState(() => _currentLink = link);
    _loadCurrentLink(resumeAt: resumePosition);
  }

  Future<void> _switchProvider(int index) async {
    if (index == _providerIndex || _switchingProvider) return;
    final provider = widget.providers[index];
    final resumePosition = _player.state.position;
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
      _currentLink = result.videoLinks!.first;
    });
    _loadCurrentLink(resumeAt: resumePosition);
  }

  Future<void> _setSpeed(double speed) async {
    setState(() => _speed = speed);
    await _player.setRate(speed);
  }

  void _skip(Duration delta) {
    final target = _player.state.position + delta;
    final clamped = target < Duration.zero ? Duration.zero : target;
    _watchSeek(clamped);
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

  // Explicit back handling: pauses playback before popping so audio/video
  // doesn't keep running in the background while the Player's dispose()
  // (which tears down the whole native mpv instance) is still in flight -
  // pause is effectively instant, dispose is not. Used by both the
  // AppBar's back button and the hardware/gesture back below.
  Future<void> _handleBack() async {
    try {
      await _player.pause();
    } catch (_) {
      // Best-effort - still proceed to pop even if pause failed/raced.
    }
    if (mounted) Navigator.of(context).pop();
  }

  // +/- 0.25s per tap, matching mpv's own default z/x keybind step size.
  // Positive delaySeconds means the subtitle track needs to appear LATER
  // (it's currently running ahead of the speech); negative means EARLIER.
  void _adjustSubtitleDelay(double deltaSeconds, void Function(void Function()) setSheetState) {
    final next = (_subtitleDelaySeconds + deltaSeconds).clamp(-30.0, 30.0);
    _subtitleDelaySeconds = next;
    final nativePlayer = _player.platform;
    if (nativePlayer is NativePlayer) {
      unawaited(nativePlayer.setProperty('sub-delay', next.toStringAsFixed(2)));
    }
    setSheetState(() {});
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

  // Subtitle picker, ported from flixquest's PlayerExternalSubtitles pattern:
  // "Off", then whatever the current provider embedded (if anything), then a
  // "Search subtitles" section that hits Wyzie Subs directly by TMDB
  // id/season/episode - so a subtitle option is always here even when the
  // winning provider has none of its own.
  void _showSubtitlesSheet() {
    var sheetOpen = true;
    final providerSubs = _result.subtitleLinks ?? const [];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
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
                    const Text(
                      'Subtitles',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    // Manual sync: fixes the common "subtitle timing is
                    // slightly off from the speech" case directly, instead
                    // of hoping a different downloaded file happens to
                    // match this exact release/cut.
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
                    const SizedBox(height: 4),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.format_color_text, color: Colors.white70),
                      title: const Text('Subtitle appearance', style: TextStyle(color: Colors.white)),
                      subtitle: const Text(
                        'Text color, background, font size',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      onTap: _showSubtitleStyleSheet,
                    ),
                    const Divider(color: Colors.white24, height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.subtitles_off, color: Colors.white70),
                      title: const Text('Off', style: TextStyle(color: Colors.white)),
                      onTap: () {
                        _player.setSubtitleTrack(SubtitleTrack.no());
                        Navigator.pop(sheetContext);
                      },
                    ),
                    if (providerSubs.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 2),
                        child: Text(
                          'From this source',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ),
                      for (final sub in providerSubs)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.subtitles_outlined, color: Colors.white70),
                          title: Text(sub.language ?? 'Unknown', style: const TextStyle(color: Colors.white)),
                          onTap: () {
                            _player.setSubtitleTrack(SubtitleTrack.uri(sub.url!, title: sub.language));
                            Navigator.pop(sheetContext);
                          },
                        ),
                    ],
                    const Padding(
                      padding: EdgeInsets.only(top: 8, bottom: 2),
                      child: Text(
                        'Search subtitles',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                    if (_loadingExternalSubtitles)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
                      )
                    else if (_externalSubtitlesError != null || _externalSubtitles.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _externalSubtitlesError != null
                                    ? 'Subtitle search failed:\n$_externalSubtitlesError'
                                    : 'No external subtitles found for this title.',
                                style: TextStyle(
                                  color: _externalSubtitlesError != null ? Colors.orangeAccent : Colors.white54,
                                  fontSize: _externalSubtitlesError != null ? 13 : 14,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                setSheetState(() {
                                  _fetchedExternalSubtitles = false;
                                  _loadingExternalSubtitles = true;
                                });
                                _fetchExternalSubtitles(setSheetState);
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _externalSubtitles.length,
                          itemBuilder: (context, index) {
                            final sub = _externalSubtitles[index];
                            // Previously-picked subtitles get a tinted
                            // background so it's obvious at a glance which
                            // ones have already been tried before. The
                            // single most recent pick gets its own distinct
                            // light-yellow highlight instead, taking
                            // priority over the general tint.
                            final isLastDownloaded =
                                _lastDownloadedSubtitleId != null && sub.id == _lastDownloadedSubtitleId;
                            final isDownloaded = _downloadedSubtitleIds.contains(sub.id);
                            final highlighted = isLastDownloaded || isDownloaded;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
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
                                unawaited(_subtitleDownloadHistory.markDownloaded(
                                mediaType: widget.mediaType,
                                tmdbId: widget.tmdbId,
                                season: widget.season,
                                episode: widget.episode,
                                subtitleId: sub.id,
                              ));
                                setState(() {
                                  _downloadedSubtitleIds = {..._downloadedSubtitleIds, sub.id};
                                  _lastDownloadedSubtitleId = sub.id;
                                });
                                _player.setSubtitleTrack(SubtitleTrack.uri(sub.url, title: sub.displayName));
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
        );
      },
    ).whenComplete(() => sheetOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final hasOtherProviders = widget.providers.length > 1;
    final hasOtherQualities = (_result.videoLinks?.length ?? 0) > 1;
    final currentProvider = widget.providers[_providerIndex];

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: _handleBack,
        ),
        title: Text('${widget.title} · ${currentProvider.displayName}', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.subtitles_outlined),
            tooltip: 'Subtitles',
            onPressed: _showSubtitlesSheet,
          ),
          PopupMenuButton<double>(
            icon: const Icon(Icons.speed),
            tooltip: 'Speed',
            onSelected: _setSpeed,
            itemBuilder: (context) => [
              for (final s in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                PopupMenuItem(
                  value: s,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (s == _speed)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.check, size: 16, color: AppTheme.accent),
                        ),
                      Text('${s}x'),
                    ],
                  ),
                ),
            ],
          ),
          if (hasOtherQualities)
            PopupMenuButton<RegularVideoLinks>(
              icon: const Icon(Icons.hd_outlined),
              tooltip: 'Quality',
              onSelected: _switchQuality,
              itemBuilder: (context) => [
                for (final link in _result.videoLinks!)
                  PopupMenuItem(
                    value: link,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (link.url == _currentLink.url)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(Icons.check, size: 16, color: AppTheme.accent),
                          ),
                        Text(link.quality ?? 'unknown quality'),
                      ],
                    ),
                  ),
              ],
            ),
          if (hasOtherProviders)
            PopupMenuButton<int>(
              icon: _switchingProvider
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: Padding(
                        padding: EdgeInsets.all(2),
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ),
                    )
                  : const Icon(Icons.dns_outlined),
              tooltip: 'Switch server',
              onSelected: _switchProvider,
              itemBuilder: (context) => [
                for (var i = 0; i < widget.providers.length; i++)
                  PopupMenuItem(
                    value: i,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (i == _providerIndex)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(Icons.check, size: 16, color: AppTheme.accent),
                          ),
                        Text(widget.providers[i].displayName),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: _error != null
          ? Center(
              child: _MessageCard(
                icon: Icons.error_outline,
                message: _error!,
                showSwitchButton: hasOtherProviders,
                onSwitch: () => _switchProvider((_providerIndex + 1) % widget.providers.length),
                onWatchEmbedded: _openWebViewFallback,
              ),
            )
          : Stack(
                // Without an explicit fit, this Stack only takes the
                // intrinsic size of its children inside the loosely
                // constrained Center it used to sit in - which could leave
                // the Video widget with zero real screen space (audio/
                // progress keeps working since the player itself doesn't
                // care about layout; you just never see a frame). Filling
                // the Scaffold body outright fixes that.
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  Video(
                    controller: _controller,
                    fit: BoxFit.contain,
                    controls: NoVideoControls,
                    subtitleViewConfiguration: SubtitleViewConfiguration(
                      style: TextStyle(
                        height: 1.4,
                        fontSize: _subtitleStyle.fontSize,
                        color: _subtitleStyle.fontColor,
                        backgroundColor: _subtitleStyle.backgroundColor,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _toggleControls,
                      onVerticalDragUpdate: (details) {
                        final size = MediaQuery.sizeOf(context);
                        _adjustVerticalControl(details, size.width, size.height);
                      },
                    ),
                  ),
                  if (!_loading && !_buffering && _controlsVisible)
                    Positioned(
                      left: 0,
                      right: 0,
                      // Deliberately not flush with the bottom edge - a
                      // seek bar glued to y=0 collides with the system
                      // back-gesture/nav-bar swipe area, which is exactly
                      // what made the default controls hard to drag.
                      bottom: 28,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: LiquidGlass(
                        borderRadius: BorderRadius.circular(16),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                                activeTrackColor: AppTheme.accent,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: AppTheme.accent,
                              ),
                              child: Slider(
                                min: 0,
                                max: _duration.inMilliseconds > 0
                                    ? _duration.inMilliseconds.toDouble()
                                    : 1,
                                value: _position.inMilliseconds
                                    .clamp(0, _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 1)
                                    .toDouble(),
                                onChangeStart: (_) => setState(() {
                                  _seeking = true;
                                  _showStuckHint = false;
                                }),
                                onChanged: (v) => setState(() => _position = Duration(milliseconds: v.toInt())),
                                onChangeEnd: (v) {
                                  final target = Duration(milliseconds: v.toInt());
                                  _watchSeek(target);
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Text(
                                    _formatDuration(_position),
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                  const Spacer(),
                                  _SkipButton(
                                    icon: Icons.replay_10,
                                    onTap: () => _skip(const Duration(seconds: -10)),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: Icon(_playing ? Icons.pause : Icons.play_arrow, color: Colors.white),
                                    onPressed: _togglePlayPause,
                                  ),
                                  const SizedBox(width: 8),
                                  _SkipButton(
                                    icon: Icons.forward_10,
                                    onTap: () => _skip(const Duration(seconds: 10)),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _formatDuration(_duration),
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        ),
                      ),
                    ),
                  if (_gestureLabel != null)
                    Center(
                      child: LiquidGlass(
                        borderRadius: BorderRadius.circular(18),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        child: Text(
                          _gestureLabel!,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  if (_loading || _buffering || _confirmingSeek)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                        const CircularProgressIndicator(color: AppTheme.accent),
                        if (_showStuckHint) ...[
                          const SizedBox(height: 20),
                          LiquidGlass(
                            margin: const EdgeInsets.symmetric(horizontal: 32),
                            borderRadius: BorderRadius.circular(16),
                            opacity: 0.72,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  "This source is taking unusually long to start - it may be down.",
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

class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: LiquidGlass(
        circular: true,
        blur: 16,
        padding: const EdgeInsets.all(10),
        child: Icon(icon, color: Colors.white, size: 26),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.message,
    required this.showSwitchButton,
    required this.onSwitch,
    required this.onWatchEmbedded,
  });

  final IconData icon;
  final String message;
  final bool showSwitchButton;
  final VoidCallback onSwitch;
  final VoidCallback onWatchEmbedded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.accent, size: 40),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (showSwitchButton)
                ElevatedButton(onPressed: onSwitch, child: const Text('Try another source')),
              OutlinedButton(onPressed: onWatchEmbedded, child: const Text('Watch via embedded player')),
            ],
          ),
        ],
      ),
    );
  }
}
