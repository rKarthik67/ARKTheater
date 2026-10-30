import 'dart:convert';
import 'dart:ui' show Color;

import 'package:http/http.dart' as http;

import '../models/media_item.dart';
import 'tmdb_service.dart';

/// Mirrors Watchly's catalogue-before-play pattern: find candidate torrents
/// for the exact TMDB/IMDb title first, then let the viewer choose one before
/// libtorrent starts peer discovery. It never searches by a loose title.
class TorrentCatalogService {
  TorrentCatalogService({http.Client? client, TmdbService? tmdb})
      : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _tmdb = tmdb ?? TmdbService();

  final http.Client _client;
  final bool _ownsClient;
  final TmdbService _tmdb;

  Future<List<TorrentSource>> findSources({
    required MediaType type,
    required int tmdbId,
    int? season,
    int? episode,
  }) async {
    try {
      final imdbId = await _tmdb.imdbId(type, tmdbId);
      if (imdbId == null) return const [];
      final torrentio = await _torrentio(
        imdbId: imdbId,
        isMovie: type == MediaType.movie,
        season: season,
        episode: episode,
      );
      if (torrentio.isNotEmpty || type != MediaType.tv) return torrentio;
      return _eztv(imdbId, season: season, episode: episode);
    } finally {
      if (_ownsClient) _client.close();
    }
  }

  Future<List<TorrentSource>> _torrentio({
    required String imdbId,
    required bool isMovie,
    int? season,
    int? episode,
  }) async {
    final id = isMovie ? imdbId : '$imdbId:$season:$episode';
    final kind = isMovie ? 'movie' : 'series';
    final uri = Uri.parse('https://torrentio.strem.fun/stream/$kind/$id.json');
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300)
      return const [];
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final streams = body['streams'] as List? ?? const [];
    return streams
        .whereType<Map>()
        .map((raw) {
          final stream = Map<String, dynamic>.from(raw);
          final hints = stream['behaviorHints'] is Map
              ? Map<String, dynamic>.from(stream['behaviorHints'] as Map)
              : const <String, dynamic>{};
          final hash =
              stream['infoHash']?.toString() ?? hints['infoHash']?.toString();
          if (hash == null || !RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(hash))
            return null;
          final title = stream['title']?.toString() ??
              stream['name']?.toString() ??
              'Torrent source';
          // Season-pack releases are extremely common for TV (far more so
          // than for movies, which are almost always single-file) -
          // Torrentio marks which file within the torrent is the actual
          // requested episode via this hint. Without it, the native engine
          // has no way to know which file to grab and falls back to
          // guessing "largest video in the torrent", which is very often
          // the wrong episode with weak seeding for that specific file -
          // the exact failure mode behind "movies play, TV episodes don't".
          final fileIndex = (hints['fileIdx'] as num?)?.toInt();
          return TorrentSource(
            title: title.replaceAll('\n', ' · '),
            source: 'Torrentio',
            magnet: _magnet(hash, title),
            seeds: _seedCount(title),
            fileIndex: fileIndex,
          );
        })
        .whereType<TorrentSource>()
        .toList(growable: false)
      ..sort((a, b) => b.score.compareTo(a.score));
  }

  Future<List<TorrentSource>> _eztv(
    String imdbId, {
    int? season,
    int? episode,
  }) async {
    final numericId = imdbId.replaceFirst(RegExp(r'^tt'), '');
    final response = await _client
        .get(Uri.parse('https://eztv.tf/api/get-torrents?imdb_id=$numericId'))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300)
      return const [];
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final torrents = body['torrents'] as List? ?? const [];
    // EZTV's API returns every torrent it has indexed for the whole show,
    // not just the requested episode - unlike Torrentio it has no
    // season/episode query parameter, so without this filter every result
    // here is effectively a random episode of the show rather than the one
    // the viewer actually selected.
    final episodePattern = (season != null && episode != null)
        ? RegExp(
            '(?:s0?$season ?e0?$episode\\b|${season}x${episode.toString().padLeft(2, '0')})',
            caseSensitive: false,
          )
        : null;
    final results = torrents
        .whereType<Map>()
        .map((raw) {
          final value = Map<String, dynamic>.from(raw);
          final magnet = value['magnet_url']?.toString();
          if (magnet == null || !magnet.startsWith('magnet:?')) return null;
          final title = value['title']?.toString() ?? 'TV torrent';
          if (episodePattern != null && !episodePattern.hasMatch(title)) {
            return null;
          }
          return TorrentSource(
            title: title,
            source: 'EZTV',
            magnet: magnet,
            seeds: value['seeds'] as int?,
          );
        })
        .whereType<TorrentSource>()
        .toList(growable: false);
    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }

  int? _seedCount(String title) {
    final match = RegExp(r'(?:👤|👥)\s*(\d+)').firstMatch(title);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  String _magnet(String hash, String name) =>
      'magnet:?xt=urn:btih:$hash&dn=${Uri.encodeQueryComponent(name)}'
      '&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce'
      '&tr=udp%3A%2F%2Fopen.stealth.si%3A80%2Fannounce'
      '&tr=udp%3A%2F%2Ftracker.torrent.eu.org%3A451%2Fannounce';
}

class TorrentSource {
  const TorrentSource({
    required this.title,
    required this.source,
    required this.magnet,
    this.seeds,
    this.fileIndex,
  });

  final String title;
  final String source;
  /// Which file within a multi-file torrent is the actual requested
  /// episode (from Torrentio's season-pack hint) - `null` for single-file
  /// releases, where there's nothing to disambiguate.
  final int? fileIndex;
  final String magnet;
  final int? seeds;

  int get score => seeds ?? 0;

  /// Watchly's own seeder-count health tiers (its Search.kt `health()`):
  /// >=100 Fast, >=20 Good, >=1 Weak, otherwise no seeds at all.
  TorrentHealth get health => switch (seeds ?? 0) {
        >= 100 => TorrentHealth.fast,
        >= 20 => TorrentHealth.good,
        >= 1 => TorrentHealth.weak,
        _ => TorrentHealth.none,
      };
}

enum TorrentHealth {
  fast('Fast', Color(0xFF4CAF50)),
  good('Good', Color(0xFF8BC34A)),
  weak('Weak', Color(0xFFFF9800)),
  none('No seeds', Color(0xFF9E9E9E));

  const TorrentHealth(this.label, this.color);

  final String label;
  final Color color;
}
