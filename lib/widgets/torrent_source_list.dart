import 'dart:async';

import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../services/torrent_catalog_service.dart';
import '../services/torrent_stream_service.dart';

/// `fileIndex` is which file within a multi-file torrent is the requested
/// episode (see [TorrentSource.fileIndex]) - `null` for single-file
/// releases, where the native engine's own "largest video file" heuristic
/// is the only option anyway. `useVlc` hands the resolved stream off to
/// the viewer's own installed VLC app instead of the in-app ExoPlayer-based
/// player - see TorrentStreamService.playInExternalVlc.
typedef TorrentPlayCallback = void Function(
  String magnet,
  int? fileIndex, {
  bool useVlc,
});

/// Always asks "App Player or VLC?" before actually playing, rather than
/// picking one silently - returns `null` if the viewer backs out.
Future<bool?> _choosePlayer(BuildContext context) => showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('Play with', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.movie_outlined),
              title: const Text('App Player'),
              subtitle: const Text('Plays inside ARKTheater'),
              onTap: () => Navigator.of(sheetContext).pop(false),
            ),
            ListTile(
              leading: const Icon(Icons.ondemand_video),
              title: const Text('VLC'),
              subtitle: const Text('Opens your installed VLC app'),
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
          ],
        ),
      ),
    );

Future<void> _selectAndPlay(
  BuildContext context,
  TorrentPlayCallback onPlay,
  String magnet,
  int? fileIndex,
) async {
  final useVlc = await _choosePlayer(context);
  if (useVlc == null) return;
  onPlay(magnet, fileIndex, useVlc: useVlc);
}

/// Watchly-style torrent picker body: a resolution tab bar (4K / 1080p /
/// 720p / All), each tab ranked fastest-seeds-first, an auto-play-best
/// shortcut, and a manual magnet fallback. Deliberately has no Scaffold/
/// AppBar of its own so it can be embedded directly on a page (see
/// EpisodeDetailScreen, which keeps the whole picker inline rather than
/// navigating away) as well as wrapped in one (see TorrentSourcesPage, used
/// from the movie detail screen).
class TorrentSourceList extends StatefulWidget {
  const TorrentSourceList({
    super.key,
    required this.mediaType,
    required this.tmdbId,
    this.season,
    this.episode,
    required this.onPlay,
  });

  final MediaType mediaType;
  final int tmdbId;
  final int? season;
  final int? episode;
  final TorrentPlayCallback onPlay;

  @override
  State<TorrentSourceList> createState() => _TorrentSourceListState();
}

class _TorrentSourceListState extends State<TorrentSourceList> {
  late Future<List<TorrentSource>> _sources;
  final _magnetController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sources = _load();
    // Fire-and-forget: starts libtorrent's session/DHT bootstrap now, in
    // parallel with the catalogue lookup above, instead of only once the
    // viewer has picked a magnet - see TorrentStreamService.warmUp.
    unawaited(TorrentStreamService.warmUp());
  }

  @override
  void dispose() {
    _magnetController.dispose();
    super.dispose();
  }

  Future<List<TorrentSource>> _load() => TorrentCatalogService().findSources(
        type: widget.mediaType,
        tmdbId: widget.tmdbId,
        season: widget.season,
        episode: widget.episode,
      );

  void _retry() => setState(() => _sources = _load());

  void _submitManualMagnet() {
    final magnet = _magnetController.text.trim();
    if (!magnet.toLowerCase().startsWith('magnet:?')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paste a complete magnet URI.')),
      );
      return;
    }
    unawaited(_selectAndPlay(context, widget.onPlay, magnet, null));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TorrentSource>>(
      future: _sources,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Could not find sources: ${snapshot.error}'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        final sources = List<TorrentSource>.from(snapshot.data ?? const [])
          ..sort((a, b) => b.score.compareTo(a.score));
        return _TorrentTabs(
          sources: sources,
          onPlay: widget.onPlay,
          magnetController: _magnetController,
          onSubmitManualMagnet: _submitManualMagnet,
        );
      },
    );
  }
}

class _TorrentTabs extends StatefulWidget {
  const _TorrentTabs({
    required this.sources,
    required this.onPlay,
    required this.magnetController,
    required this.onSubmitManualMagnet,
  });

  final List<TorrentSource> sources;
  final TorrentPlayCallback onPlay;
  final TextEditingController magnetController;
  final VoidCallback onSubmitManualMagnet;

  @override
  State<_TorrentTabs> createState() => _TorrentTabsState();
}

class _TorrentTabsState extends State<_TorrentTabs>
    with SingleTickerProviderStateMixin {
  static const _tabs = ['4K', '1080p', '720p', 'All'];
  late final TabController _tabController =
      TabController(length: _tabs.length, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _is4k(String t) => t.contains('2160') || t.contains('4k');
  bool _is1080p(String t) => t.contains('1080');
  bool _is720p(String t) => t.contains('720');

  List<TorrentSource> _forTab(int index) {
    if (index == 3) return widget.sources; // All, already seed-sorted.
    return widget.sources.where((source) {
      final t = source.title.toLowerCase();
      return switch (index) {
        0 => _is4k(t),
        1 => _is1080p(t),
        _ => _is720p(t),
      };
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.sources.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No torrent sources found.'),
          )
        else ...[
          FilledButton.icon(
            onPressed: () => _selectAndPlay(context, widget.onPlay,
                widget.sources.first.magnet, widget.sources.first.fileIndex),
            icon: const Icon(Icons.auto_awesome),
            label:
                Text('Auto play best · ${widget.sources.first.seeds ?? 0} seeds'),
          ),
          const SizedBox(height: 16),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final label in _tabs) Tab(text: label)],
          ),
          SizedBox(
            // A fixed height keeps this usable both standalone (where the
            // outer ListView can scroll) and embedded inline on
            // EpisodeDetailScreen (where this whole widget sits inside
            // another scrollable) - TabBarView can't size itself from its
            // children the way a plain Column can.
            height: 360,
            child: TabBarView(
              controller: _tabController,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  _TorrentSourceColumn(
                    sources: _forTab(i),
                    onPlay: widget.onPlay,
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text('Manual magnet', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        TextField(
          controller: widget.magnetController,
          minLines: 2,
          maxLines: 4,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Magnet URI',
            hintText: 'magnet:?xt=urn:btih:...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: widget.onSubmitManualMagnet,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Buffer and play'),
        ),
        const SizedBox(height: 12),
        Text(
          'Torrent playback is currently available on Android. Availability depends on active peers and file format.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _TorrentSourceColumn extends StatelessWidget {
  const _TorrentSourceColumn({required this.sources, required this.onPlay});

  final List<TorrentSource> sources;
  final TorrentPlayCallback onPlay;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) {
      return const Center(child: Text('No sources in this resolution.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: sources.length,
      itemBuilder: (context, index) {
        final source = sources[index];
        final health = source.health;
        return Card(
          child: ListTile(
            leading: const Icon(Icons.hub_outlined),
            title: Text(source.title,
                maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration:
                      BoxDecoration(color: health.color, shape: BoxShape.circle),
                ),
                Flexible(
                  child: Text(
                    '${health.label} · ${source.source} · ${source.seeds ?? 0} seeds',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            onTap: () =>
                _selectAndPlay(context, onPlay, source.magnet, source.fileIndex),
            trailing: IconButton(
              tooltip: 'Download',
              icon: const Icon(Icons.download_outlined),
              onPressed: () async {
                await TorrentStreamService.queueDownload(source.magnet);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Download queued in ARKTheater.')));
                }
              },
            ),
          ),
        );
      },
    );
  }
}
