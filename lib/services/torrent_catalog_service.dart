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
    String? customIndexerUrl,
  }) async {
    try {
      final imdbId = await _tmdb.imdbId(type, tmdbId);
      if (imdbId == null) return const [];
      final titleAndYear = await _tmdb.titleAndYear(type, tmdbId);

      // Torrentio, Pirate Bay, Nyaa, (movies only) YTS, and an optional
      // viewer-configured indexer all run together and merge - if one is
      // slow, down, or outright unreachable (e.g. a connection reset), the
      // viewer still sees the others' results instead of nothing. Each call
      // is wrapped with _safe() specifically so a single bad network error
      // can't make Future.wait reject the whole batch - that's the bug a
      // missing per-source try/catch caused here before.
      final results = await Future.wait([
        _safe(_torrentio(
          imdbId: imdbId,
          isMovie: type == MediaType.movie,
          season: season,
          episode: episode,
        )),
        if (titleAndYear != null) ...[
          _safe(_pirateBay(titleAndYear, season: season, episode: episode)),
          _safe(_nyaa(titleAndYear, season: season, episode: episode)),
          if (type == MediaType.movie) _safe(_yts(titleAndYear)),
          if (customIndexerUrl != null)
            _safe(_customIndexer(customIndexerUrl, titleAndYear,
                season: season, episode: episode)),
        ],
      ]);
      final merged = _dedupeByMagnet(results.expand((list) => list));
      if (merged.isNotEmpty || type != MediaType.tv) return merged;
      return await _safe(_eztv(imdbId, season: season, episode: episode));
    } finally {
      if (_ownsClient) _client.close();
    }
  }

  /// Isolates one indexer's failure from the rest of the batch - a thrown
  /// error here (timeout, socket reset, malformed response, ...) becomes an
  /// empty result for that one source instead of failing every source.
  Future<List<TorrentSource>> _safe(Future<List<TorrentSource>> source) async {
    try {
      return await source;
    } catch (_) {
      return const [];
    }
  }

  /// Keeps the first (best-ranked) copy of any torrent that more than one
  /// indexer happens to return - Torrentio already aggregates from several
  /// trackers including Pirate Bay itself, so the same release showing up
  /// twice is expected, not a bug.
  List<TorrentSource> _dedupeByMagnet(Iterable<TorrentSource> sources) {
    final seen = <String>{};
    final unique = <TorrentSource>[];
    for (final source in sources) {
      final hash = RegExp(r'btih:([a-fA-F0-9]{40})')
          .firstMatch(source.magnet)
          ?.group(1)
          ?.toLowerCase();
      if (hash != null && !seen.add(hash)) continue;
      unique.add(source);
    }
    return unique;
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
    final episodePattern = _episodePattern(season, episode);
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

  /// apibay.org is the actual Pirate Bay search backend (the same data the
  /// real site and its mirrors query), not a scrape of any one proxy page -
  /// so it isn't affected by proxy domains changing. It only takes a
  /// free-text query (no IMDb id support), so the viewer-facing title+year
  /// string is what gets searched; a "no results" search still returns one
  /// placeholder row with an all-zero info_hash, which is filtered out here.
  Future<List<TorrentSource>> _pirateBay(
    String titleAndYear, {
    int? season,
    int? episode,
  }) =>
      _apibayShaped(
        Uri.parse(
            'https://apibay.org/q.php?q=${Uri.encodeQueryComponent(titleAndYear)}'),
        source: 'Pirate Bay',
        season: season,
        episode: episode,
      );

  /// A viewer-configured torrent search API (Settings -> Stream Sources ->
  /// Custom torrent indexer) that returns the same apibay.org JSON shape -
  /// works for any site exposing that shape, not just Pirate Bay mirrors.
  Future<List<TorrentSource>> _customIndexer(
    String baseUrl,
    String titleAndYear, {
    int? season,
    int? episode,
  }) {
    final separator = baseUrl.contains('?') ? '&' : '?';
    return _apibayShaped(
      Uri.parse('$baseUrl${separator}q=${Uri.encodeQueryComponent(titleAndYear)}'),
      source: 'Custom indexer',
      season: season,
      episode: episode,
    );
  }

  Future<List<TorrentSource>> _apibayShaped(
    Uri uri, {
    required String source,
    int? season,
    int? episode,
  }) async {
    final response = await _client.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) return const [];
    final List results;
    try {
      results = jsonDecode(response.body) as List? ?? const [];
    } catch (_) {
      return const [];
    }
    final episodePattern = _episodePattern(season, episode);
    final sources = results
        .whereType<Map>()
        .map((raw) {
          final value = Map<String, dynamic>.from(raw);
          final hash = value['info_hash']?.toString();
          if (hash == null ||
              !RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(hash) ||
              RegExp(r'^0+$').hasMatch(hash)) {
            return null;
          }
          final name = value['name']?.toString() ?? 'Torrent source';
          if (episodePattern != null && !episodePattern.hasMatch(name)) {
            return null;
          }
          return TorrentSource(
            title: name,
            source: source,
            magnet: _magnet(hash, name),
            seeds: int.tryParse(value['seeders']?.toString() ?? ''),
          );
        })
        .whereType<TorrentSource>()
        .toList(growable: false);
    sources.sort((a, b) => b.score.compareTo(a.score));
    return sources;
  }

  /// Nyaa's own RSS search (official, not a scrape of the HTML site) -
  /// mainly anime/Asian content, so a Hollywood title search here will
  /// legitimately come back empty rather than errored.
  Future<List<TorrentSource>> _nyaa(
    String titleAndYear, {
    int? season,
    int? episode,
  }) async {
    final uri = Uri.parse(
        'https://nyaa.si/?page=rss&q=${Uri.encodeQueryComponent(titleAndYear)}');
    final response = await _client.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) return const [];
    final episodePattern = _episodePattern(season, episode);
    final sources = <TorrentSource>[];
    for (final item in RegExp(r'<item>([\s\S]*?)<\/item>').allMatches(response.body)) {
      final block = item.group(1) ?? '';
      final hash =
          RegExp(r'<nyaa:infoHash>([a-fA-F0-9]{40})<\/nyaa:infoHash>')
              .firstMatch(block)
              ?.group(1);
      if (hash == null) continue;
      final title = RegExp(r'<title>([\s\S]*?)<\/title>')
              .firstMatch(block)
              ?.group(1)
              ?.replaceAll('&#34;', '"')
              .replaceAll('&amp;', '&') ??
          'Torrent source';
      if (episodePattern != null && !episodePattern.hasMatch(title)) continue;
      final seeds = int.tryParse(
          RegExp(r'<nyaa:seeders>(\d+)<\/nyaa:seeders>').firstMatch(block)?.group(1) ?? '');
      sources.add(TorrentSource(
        title: title,
        source: 'Nyaa',
        magnet: _magnet(hash, title),
        seeds: seeds,
      ));
    }
    sources.sort((a, b) => b.score.compareTo(a.score));
    return sources;
  }

  /// YTS's official public API (movies only - it has no TV catalogue).
  /// yts.mx itself no longer resolves at all (NXDOMAIN, checked 2026-11-01) -
  /// YTS runs the same API on several mirror TLDs simultaneously rather than
  /// one canonical domain, and yts.am is the one used here. Unverified live
  /// from this environment (connection to every piracy-indexer domain tried
  /// here got reset at the TLS handshake, likely a network-level block, not
  /// a code issue) - if this stops working, check which YTS mirror is
  /// currently live and swap the host below.
  Future<List<TorrentSource>> _yts(String titleAndYear) async {
    final uri = Uri.parse(
        'https://yts.am/api/v2/list_movies.json?query_term=${Uri.encodeQueryComponent(titleAndYear)}');
    final response = await _client.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) return const [];
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final movies = (body['data'] as Map?)?['movies'] as List? ?? const [];
    final sources = <TorrentSource>[];
    for (final raw in movies.whereType<Map>()) {
      final movie = Map<String, dynamic>.from(raw);
      final movieTitle = movie['title_long']?.toString() ?? movie['title']?.toString() ?? 'Movie';
      final torrents = movie['torrents'] as List? ?? const [];
      for (final rawTorrent in torrents.whereType<Map>()) {
        final torrent = Map<String, dynamic>.from(rawTorrent);
        final hash = torrent['hash']?.toString();
        if (hash == null || !RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(hash)) continue;
        final quality = torrent['quality']?.toString() ?? '';
        final type = torrent['type']?.toString() ?? '';
        sources.add(TorrentSource(
          title: '$movieTitle [$quality${type.isEmpty ? '' : ' $type'}]',
          source: 'YTS',
          magnet: _magnet(hash, movieTitle),
          seeds: (torrent['seeds'] as num?)?.toInt(),
        ));
      }
    }
    sources.sort((a, b) => b.score.compareTo(a.score));
    return sources;
  }

  RegExp? _episodePattern(int? season, int? episode) =>
      (season != null && episode != null)
          ? RegExp(
              '(?:s0?$season ?e0?$episode\\b|${season}x${episode.toString().padLeft(2, '0')})',
              caseSensitive: false,
            )
          : null;

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
