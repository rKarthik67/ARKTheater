import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../widgets/torrent_source_list.dart';

/// Full-page wrapper around [TorrentSourceList] for entry points that
/// navigate to a dedicated torrent picker (the movie detail screen's
/// "Torrent" button). Episode pages instead embed [TorrentSourceList]
/// inline - see EpisodeDetailScreen.
class TorrentSourcesPage extends StatelessWidget {
  const TorrentSourcesPage({
    super.key,
    required this.title,
    required this.mediaType,
    required this.tmdbId,
    this.season,
    this.episode,
    required this.onPlay,
  });

  final String title;
  final MediaType mediaType;
  final int tmdbId;
  final int? season;
  final int? episode;
  final TorrentPlayCallback onPlay;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: TorrentSourceList(
            mediaType: mediaType,
            tmdbId: tmdbId,
            season: season,
            episode: episode,
            onPlay: (magnet, fileIndex, {useVlc = false}) {
              Navigator.of(context).pop();
              onPlay(magnet, fileIndex, useVlc: useVlc);
            },
          ),
        ),
      );
}
