import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/media_detail.dart';
import '../models/media_item.dart';
import '../services/tmdb_service.dart';
import '../services/torrent_stream_service.dart';
import '../state/recently_watched_provider.dart';
import '../state/watchlist_provider.dart';
import '../video_providers/common.dart';
import '../video_providers/names.dart';
import '../widgets/torrent_source_list.dart';
import 'player_screen.dart';

/// Scraper/Embed delegate back to the parent DetailScreen (and pop first -
/// unchanged). Torrent sources are handled entirely on this screen instead:
/// the picker and the "finding peers" status both stay inline here rather
/// than navigating to a separate page or updating state hidden behind this
/// one - see _playTorrent.
class EpisodeDetailScreen extends StatefulWidget {
  const EpisodeDetailScreen({
    super.key,
    required this.item,
    required this.season,
    required this.episode,
    required this.onScraper,
    required this.onEmbed,
  });

  final MediaItem item;
  final int season;
  final EpisodeSummary episode;
  final VoidCallback onScraper;
  final VoidCallback onEmbed;

  @override
  State<EpisodeDetailScreen> createState() => _EpisodeDetailScreenState();
}

class _EpisodeDetailScreenState extends State<EpisodeDetailScreen> {
  bool _showTorrent = false;
  bool _resolving = false;
  String? _resolvingStatus;
  StreamSubscription<TorrentStreamStatus>? _statusSubscription;

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _playTorrent(
    String magnet,
    int? fileIndex, {
    bool useVlc = false,
  }) async {
    setState(() {
      _resolving = true;
      _resolvingStatus = 'Connecting to torrent peers...';
    });
    try {
      _statusSubscription = TorrentStreamService.statuses.listen((status) {
        if (mounted) setState(() => _resolvingStatus = status.label);
      });
      final torrent =
          await TorrentStreamService.startMagnet(magnet, fileIndex: fileIndex);
      if (!mounted) return;
      await _statusSubscription?.cancel();
      _statusSubscription = null;
      if (useVlc) {
        await TorrentStreamService.playInExternalVlc(
          url: torrent.fileUri,
          title:
              '${widget.item.title} - S${widget.season}E${widget.episode.episodeNumber}',
        );
        await context
            .read<WatchlistProvider>()
            .markWatched(widget.item.type, widget.item.id);
        await context.read<RecentlyWatchedProvider>().record(
              item: widget.item,
              season: widget.season,
              episode: widget.episode.episodeNumber,
            );
        return;
      }
      const providers = [
        VideoProvider(
          fullName: 'Torrent source',
          codeName: 'local:torrent',
          alias: 'Torrent source',
        ),
      ];
      final result = ProviderLoadResult(
        success: true,
        videoLinks: [
          RegularVideoLinks(
            url: torrent.fileUri,
            quality: 'Torrent',
            server: 'Torrent source',
          ),
        ],
      );
      await context
          .read<WatchlistProvider>()
          .markWatched(widget.item.type, widget.item.id);
      await context.read<RecentlyWatchedProvider>().record(
            item: widget.item,
            season: widget.season,
            episode: widget.episode.episodeNumber,
          );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            title:
                '${widget.item.title} - S${widget.season}E${widget.episode.episodeNumber}',
            mediaType: widget.item.type,
            tmdbId: widget.item.id,
            season: widget.season,
            episode: widget.episode.episodeNumber,
            providers: providers,
            initialProviderIndex: 0,
            initialResult: result,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start torrent source: $error')),
      );
    } finally {
      await _statusSubscription?.cancel();
      _statusSubscription = null;
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final episode = widget.episode;
    return Scaffold(
      appBar: AppBar(title: Text('S${widget.season} E${episode.episodeNumber}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (episode.stillUrl(size: 'w780') != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: CachedNetworkImage(
                  imageUrl: episode.stillUrl(size: 'w780')!,
                  height: 210,
                  fit: BoxFit.cover),
            ),
          const SizedBox(height: 16),
          Text(episode.name, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(episode.overview ?? 'No episode description is available.'),
          const SizedBox(height: 22),
          Text('Watch options', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: const Text('Scraper sources'),
              subtitle: const Text('Find regular stream providers'),
              onTap: widget.onScraper),
          ListTile(
              leading: const Icon(Icons.open_in_browser),
              title: const Text('Embedded player'),
              subtitle: const Text('Open an embed source'),
              onTap: widget.onEmbed),
          ListTile(
            leading: const Icon(Icons.hub_outlined),
            title: const Text('Torrent sources'),
            subtitle: const Text('4K, 1080p, 720p and fastest auto choice'),
            trailing:
                Icon(_showTorrent ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _showTorrent = !_showTorrent),
          ),
          if (_showTorrent)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _resolving
                  ? Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_resolvingStatus ??
                              'Connecting to torrent peers...'),
                        ),
                      ],
                    )
                  : TorrentSourceList(
                      mediaType: MediaType.tv,
                      tmdbId: widget.item.id,
                      season: widget.season,
                      episode: episode.episodeNumber,
                      onPlay: _playTorrent,
                    ),
            ),
          const SizedBox(height: 20),
          Text('Episode cast', style: Theme.of(context).textTheme.titleLarge),
          FutureBuilder<List<CastMember>>(
            future: TmdbService()
                .episodeCast(widget.item.id, widget.season, episode.episodeNumber),
            builder: (_, snapshot) {
              if (!snapshot.hasData)
                return const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator());
              return Wrap(spacing: 12, runSpacing: 12, children: [
                for (final cast in snapshot.data!)
                  SizedBox(
                      width: 82,
                      child: Column(children: [
                        CircleAvatar(
                            radius: 30,
                            backgroundImage: cast.profilePath == null
                                ? null
                                : CachedNetworkImageProvider(
                                    'https://image.tmdb.org/t/p/w185${cast.profilePath}')),
                        const SizedBox(height: 4),
                        Text(cast.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center),
                      ])),
              ]);
            },
          ),
        ],
      ),
    );
  }
}
