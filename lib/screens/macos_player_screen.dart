import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
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

/// macOS-only playback screen, built on Flutter's official `video_player`
/// package (its `video_player_avfoundation` backend) instead of media_kit.
///
/// Why this file exists separately from DesktopPlayerScreen: that screen's
/// mpv/libmpv engine (shared with Windows/Linux) was found to hang
/// indefinitely on some scraped CDNs when seeking to a not-yet-buffered
/// position - confirmed by direct logging that the CDN sometimes never
/// delivers the byte range mpv's demuxer asked for, no matter how many
/// times the connection is retried or reopened. iPad/Android never show
/// this because better_player_plus's iOS build already talks to Apple's
/// AVPlayer/AVFoundation directly - so this screen gets macOS onto that
/// exact same underlying engine via the one Flutter plugin that reaches it
/// on desktop (better_player_plus itself has no macOS implementation at
/// all).
///
/// Trade-off: `video_player` is deliberately minimal - no built-in
/// subtitle rendering, no quality/track menu, no stuck-seek watchdog. All
/// of that is reimplemented here from scratch (a small SRT/VTT parser and
/// a plain Text overlay for subtitles; a simple one-shot "taking a while"
/// hint instead of DesktopPlayerScreen's reopen-and-retry dance, since
/// AVPlayer is expected to handle reconnection internally rather than
/// needing that workaround).
class MacosPlayerScreen extends StatefulWidget {
  const MacosPlayerScreen({
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
  State<MacosPlayerScreen> createState() => _MacosPlayerScreenState();
}

class _SubtitleCue {
  const _SubtitleCue({required this.start, required this.end, required this.text});
  final Duration start;
  final Duration end;
  final String text;
}

/// Minimal, dependency-free SRT/WebVTT parser - good enough for the plain
/// dialogue-line subtitle files this app deals with (scraper-embedded or
/// Wyzie Subs). Strips basic <tag>-style markup some SRT files carry.
List<_SubtitleCue> _parseSubtitleCues(String raw) {
  final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final blocks = normalized.split(RegExp(r'\n\s*\n'));
  final timeRe = RegExp(
    r'(\d{1,2}):(\d{2}):(\d{2})[.,](\d{1,3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[.,](\d{1,3})',
  );
  final cues = <_SubtitleCue>[];

  Duration parseGroup(RegExpMatch match, int offset) {
    final h = int.parse(match.group(offset)!);
    final m = int.parse(match.group(offset + 1)!);
    final s = int.parse(match.group(offset + 2)!);
    final msRaw = match.group(offset + 3)!.padRight(3, '0').substring(0, 3);
    return Duration(hours: h, minutes: m, seconds: s, milliseconds: int.parse(msRaw));
  }

  for (final block in blocks) {
    final lines = block.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) continue;
    RegExpMatch? match;
    var textStart = 0;
    for (var i = 0; i < lines.length; i++) {
      final m = timeRe.firstMatch(lines[i]);
      if (m != null) {
        match = m;
        textStart = i + 1;
        break;
      }
    }
    if (match == null) continue;
    final start = parseGroup(match, 1);
    final end = parseGroup(match, 5);
    final text = lines
        .sublist(textStart)
        .join('\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\{[^}]*\}'), '')
        .trim();
    if (text.isNotEmpty) {
      cues.add(_SubtitleCue(start: start, end: end, text: text));
    }
  }
  cues.sort((a, b) => a.start.compareTo(b.start));
  return cues;
}

String? _lookupSubtitleText(List<_SubtitleCue> cues, Duration position) {
  for (final cue in cues) {
    if (position < cue.start) break;
    if (position <= cue.end) return cue.text;
  }
  return null;
}

class _MacosPlayerScreenState extends State<MacosPlayerScreen> {
  final _playbackPosition = PlaybackPositionService();
  final _subtitleDownloadHistory = SubtitleDownloadHistoryService();

  VideoPlayerController? _controller;

  late int _providerIndex;
  late ProviderLoadResult _result;
  late RegularVideoLinks _currentLink;

  bool _loading = true;
  bool _switchingProvider = false;
  String? _error;

  bool _playing = false;
  bool _seeking = false;
  bool _confirmingSeek = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _speed = 1.0;

  Timer? _positionSaveTimer;
  Timer? _stuckTimer;
  bool _showStuckHint = false;
  Duration _lastProgressPosition = Duration.zero;
  static const _displayChannel = MethodChannel('ark_theater/display');
  Timer? _gestureLabelTimer;
  bool _controlsVisible = true;
  double _brightness = 0.5;
  String? _gestureLabel;

  SubtitleStyle _subtitleStyle = SubtitleStyle.defaultStyle;
  double _subtitleDelaySeconds = 0.0;
  List<_SubtitleCue> _activeCues = const [];
  String? _activeSubtitleUrl;
  // Alignment is normalized to the player bounds, so the selected placement
  // continues to make sense if the iPad rotates during playback.
  Alignment _subtitleAlignment = const Alignment(0, 0.72);

  Set<String> _downloadedSubtitleIds = const {};
  String? _lastDownloadedSubtitleId;

  List<ExternalSubtitle> _externalSubtitles = const [];
  bool _fetchedExternalSubtitles = false;
  bool _loadingExternalSubtitles = false;
  String? _externalSubtitlesError;

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

  @override
  void initState() {
    super.initState();
    _providerIndex = widget.initialProviderIndex;
    _result = widget.initialResult;
    _currentLink = _result.videoLinks!.first;
    unawaited(_loadSubtitleDownloadHistory());
    unawaited(_loadSubtitleStyle());
    WakelockPlus.enable();
    unawaited(_loadBrightness());
    _loadCurrentLink();
  }

  Future<void> _loadBrightness() async {
    try {
      final value = await _displayChannel.invokeMethod<double>('getBrightness');
      if (mounted && value != null) setState(() => _brightness = value.clamp(0.0, 1.0).toDouble());
    } catch (_) {}
  }

  void _showGestureLabel(String value) {
    _gestureLabelTimer?.cancel();
    setState(() => _gestureLabel = value);
    _gestureLabelTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _gestureLabel = null);
    });
  }

  void _adjustVerticalControl(DragUpdateDetails details, Size size) {
    final delta = -details.delta.dy / size.height;
    if (details.localPosition.dx < size.width / 2) {
      _brightness = (_brightness + delta).clamp(0.0, 1.0).toDouble();
      unawaited(_displayChannel.invokeMethod<void>('setBrightness', _brightness));
      _showGestureLabel('Brightness ${(_brightness * 100).round()}%');
    } else {
      final controller = _controller;
      if (controller == null) return;
      final volume = (controller.value.volume + delta).clamp(0.0, 1.0).toDouble();
      unawaited(controller.setVolume(volume));
      _showGestureLabel('Volume ${(volume * 100).round()}%');
    }
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

  Future<void> _loadSubtitleStyle() async {
    final style = await SubtitleStyleService().load();
    if (mounted) setState(() => _subtitleStyle = style);
  }

  void _onSubtitleStyleChanged(SubtitleStyle style) {
    setState(() => _subtitleStyle = style);
    unawaited(SubtitleStyleService().save(style));
  }

  Future<void> _loadCurrentLink({Duration? resumeAt}) async {
    _stuckTimer?.cancel();
    _lastProgressPosition = Duration.zero;
    final oldController = _controller;
    setState(() {
      _loading = true;
      _error = null;
      _showStuckHint = false;
      _confirmingSeek = false;
      _seeking = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      _activeCues = const [];
      _activeSubtitleUrl = null;
    });

    if (oldController != null) {
      oldController.removeListener(_onControllerUpdate);
      unawaited(oldController.dispose());
    }

    try {
      final format = _currentLink.isM3U8 == true
          ? VideoFormat.hls
          : _currentLink.isDash == true
              ? VideoFormat.dash
              : VideoFormat.other;
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(_currentLink.url!),
        httpHeaders: _currentLink.headers ?? const {},
        formatHint: format,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onControllerUpdate);
      _controller = controller;
      _duration = controller.value.duration;

      final subs = _result.subtitleLinks ?? const [];
      if (subs.isNotEmpty) {
        unawaited(_selectEmbeddedSubtitle(subs.first));
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
        await controller.seekTo(target);
        if (fromStorage && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Resumed from ${_formatDuration(target)}')),
          );
        }
      }

      await controller.setPlaybackSpeed(_speed);
      await controller.play();

      _positionSaveTimer?.cancel();
      _positionSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted || _controller == null) return;
        unawaited(_playbackPosition.save(
          mediaType: widget.mediaType,
          tmdbId: widget.tmdbId,
          season: widget.season,
          episode: widget.episode,
          position: _position,
          duration: _duration,
        ).then(_onPositionSaved));
      });

      _armStuckTimer();
    } catch (err) {
      if (mounted) setState(() => _error = 'Playback failed: $err');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onControllerUpdate() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final value = controller.value;
    if (value.hasError && _error == null) {
      setState(() => _error = 'Playback error: ${value.errorDescription}');
      return;
    }
    if (value.position > _lastProgressPosition + const Duration(milliseconds: 500)) {
      _lastProgressPosition = value.position;
      if (_showStuckHint) setState(() => _showStuckHint = false);
    }
    setState(() {
      _playing = value.isPlaying;
      _duration = value.duration;
      if (!_seeking) _position = value.position;
    });
  }

  void _armStuckTimer() {
    _stuckTimer?.cancel();
    final referencePosition = _controller?.value.position ?? Duration.zero;
    _stuckTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted || _controller == null) return;
      if (_controller!.value.position <= referencePosition + const Duration(milliseconds: 500)) {
        setState(() => _showStuckHint = true);
      }
    });
  }

  void _watchSeek(Duration target) {
    _stuckTimer?.cancel();
    setState(() {
      _seeking = true;
      _confirmingSeek = true;
      _position = target;
    });
    final controller = _controller;
    if (controller == null) return;
    unawaited(controller.seekTo(target));

    _stuckTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      final current = _controller?.value.position ?? Duration.zero;
      final buffering = _controller?.value.isBuffering ?? false;
      final onTarget = (current - target).abs() <= const Duration(seconds: 6) && !buffering;
      setState(() {
        _seeking = false;
        _confirmingSeek = false;
        _showStuckHint = !onTarget;
      });
    });
  }

  void _skip(Duration delta) {
    final current = _controller?.value.position ?? Duration.zero;
    final target = current + delta;
    _watchSeek(target < Duration.zero ? Duration.zero : target);
  }

  Future<void> _togglePlayPause() async {
    final controller = _controller;
    if (controller == null) return;
    if (_playing) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  Future<void> _setSpeed(double speed) async {
    setState(() => _speed = speed);
    await _controller?.setPlaybackSpeed(speed);
  }

  void _switchQuality(RegularVideoLinks link) {
    if (link.url == _currentLink.url) return;
    final resumePosition = _controller?.value.position ?? Duration.zero;
    setState(() => _currentLink = link);
    _loadCurrentLink(resumeAt: resumePosition);
  }

  Future<void> _switchProvider(int index) async {
    if (index == _providerIndex || _switchingProvider) return;
    final provider = widget.providers[index];
    final resumePosition = _controller?.value.position ?? Duration.zero;
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

  Future<void> _selectEmbeddedSubtitle(RegularSubtitleLinks sub) async {
    final url = sub.url;
    if (url == null) return;
    try {
      final response = await http.get(Uri.parse(url), headers: sub.headers);
      final cues = _parseSubtitleCues(utf8.decode(response.bodyBytes, allowMalformed: true));
      if (!mounted) return;
      setState(() {
        _activeCues = cues;
        _activeSubtitleUrl = url;
      });
    } catch (_) {
      // Best-effort - a broken embedded subtitle just means no subtitles
      // rather than a crash.
    }
  }

  Future<void> _selectExternalSubtitle(ExternalSubtitle sub) async {
    try {
      final response = await http.get(Uri.parse(sub.url));
      final cues = _parseSubtitleCues(utf8.decode(response.bodyBytes, allowMalformed: true));
      if (!mounted) return;
      setState(() {
        _activeCues = cues;
        _activeSubtitleUrl = sub.url;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load that subtitle: $e')),
        );
      }
    }
  }

  void _selectNoSubtitle() {
    setState(() {
      _activeCues = const [];
      _activeSubtitleUrl = null;
    });
  }

  void _adjustSubtitleDelay(double deltaSeconds, void Function(void Function()) setSheetState) {
    final next = (_subtitleDelaySeconds + deltaSeconds).clamp(-30.0, 30.0);
    setState(() => _subtitleDelaySeconds = next);
    setSheetState(() {});
  }

  String? _currentSubtitleText() {
    if (_activeCues.isEmpty) return null;
    final adjusted = _position - Duration(milliseconds: (_subtitleDelaySeconds * 1000).round());
    return _lookupSubtitleText(_activeCues, adjusted);
  }

  void _moveSubtitle(DragUpdateDetails details, Size playerSize) {
    if (playerSize.isEmpty) return;
    setState(() {
      _subtitleAlignment = Alignment(
        (_subtitleAlignment.x + (details.delta.dx * 2 / playerSize.width)).clamp(-1.0, 1.0).toDouble(),
        (_subtitleAlignment.y + (details.delta.dy * 2 / playerSize.height)).clamp(-1.0, 1.0).toDouble(),
      );
    });
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
      _externalSubtitlesError = error.toString();
    } finally {
      _fetchedExternalSubtitles = true;
      _loadingExternalSubtitles = false;
      setSheetState(() {});
    }
  }

  void _showSubtitleStyleSheet() {
    showSubtitleStyleSheet(
      context: context,
      current: _subtitleStyle,
      onChanged: _onSubtitleStyleChanged,
    );
  }

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
                        _selectNoSubtitle();
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
                            unawaited(_selectEmbeddedSubtitle(sub));
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
                                unawaited(_selectExternalSubtitle(sub));
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
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
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

  @override
  void dispose() {
    _gestureLabelTimer?.cancel();
    _stuckTimer?.cancel();
    _positionSaveTimer?.cancel();
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_onControllerUpdate);
      unawaited(_playbackPosition.save(
        mediaType: widget.mediaType,
        tmdbId: widget.tmdbId,
        season: widget.season,
        episode: widget.episode,
        position: controller.value.position,
        duration: controller.value.duration,
      ).then(_onPositionSaved));
      unawaited(controller.dispose());
    }
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasOtherProviders = widget.providers.length > 1;
    final hasOtherQualities = (_result.videoLinks?.length ?? 0) > 1;
    final currentProvider = widget.providers[_providerIndex];
    final buffering = _controller?.value.isBuffering ?? false;
    final subtitleText = _currentSubtitleText();

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // The player must be laid out against the complete display.  On
        // iPad, reserving the AppBar's height moves the body's visual centre
        // below the physical screen centre (and AVPlayer makes that especially
        // noticeable with letterboxed video).  Keep the controls over the
        // video instead of taking space away from it.
        extendBodyBehindAppBar: true,
        // The toolbar stays mounted while hidden, so toggling controls cannot
        // cause a layout shift.
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: IgnorePointer(
            ignoring: !_controlsVisible,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: AppBar(
          backgroundColor: Colors.black,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: _handleBack,
          ),
          title: Text('${widget.title} · ${currentProvider.displayName}', overflow: TextOverflow.ellipsis),
          actions: [
            // Keep AVPlayer's video load/buffer indicator unobtrusive: it
            // belongs beside the subtitle control, not over the video.
            if (_loading || buffering || _confirmingSeek)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.subtitles_outlined),
              tooltip: 'Subtitles (drag active subtitles to move them)',
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
                icon: const Icon(Icons.high_quality_outlined),
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
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                      )
                    : const Icon(Icons.dns_outlined),
                tooltip: 'Source',
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
            ),
          ),
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
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  if (_controller != null && _controller!.value.isInitialized)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final screenSize = constraints.biggest;
                        final aspectRatio = _controller!.value.aspectRatio;
                        final screenAspectRatio = screenSize.width / screenSize.height;
                        final videoSize = screenAspectRatio > aspectRatio
                            ? Size(screenSize.height * aspectRatio, screenSize.height)
                            : Size(screenSize.width, screenSize.width / aspectRatio);

                        return Center(
                          child: SizedBox(
                            width: videoSize.width,
                            height: videoSize.height,
                            child: VideoPlayer(_controller!),
                          ),
                        );
                      },
                    ),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => setState(() => _controlsVisible = !_controlsVisible),
                      onVerticalDragUpdate: (details) =>
                          _adjustVerticalControl(details, MediaQuery.sizeOf(context)),
                    ),
                  ),
                  if (subtitleText != null && !_loading)
                    Align(
                      alignment: _subtitleAlignment,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanUpdate: (details) => _moveSubtitle(details, MediaQuery.sizeOf(context)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _subtitleStyle.backgroundColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              subtitleText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                height: 1.4,
                                fontSize: _subtitleStyle.fontSize,
                                color: _subtitleStyle.fontColor,
                                shadows: const [
                                  Shadow(color: Colors.black, blurRadius: 4),
                                  Shadow(color: Colors.black, blurRadius: 8),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (!_loading && !buffering && !_confirmingSeek && _controlsVisible)
                    Positioned(
                      left: 0,
                      right: 0,
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
                                  _watchSeek(Duration(milliseconds: v.toInt()));
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
                        child: Text(_gestureLabel!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  // Do not cover the iPad video with a spinner while AVPlayer
                  // is starting, buffering, or seeking.  A stalled source is
                  // still surfaced after the watchdog has enough evidence.
                  if (_showStuckHint)
                    Center(
                      child: LiquidGlass(
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
                                    onPressed: () => _switchProvider(
                                      (_providerIndex + 1) % widget.providers.length,
                                    ),
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
