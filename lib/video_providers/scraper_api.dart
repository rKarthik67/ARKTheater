import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'common.dart';
import 'names.dart';

/// Client for ARKVideoScrapper's `/api/v2` routes - ported from flixquest's
/// `ScraperApi` client against the same API shape (ARKVideoScrapper is a
/// fork of flixquest-scraper, so the routes match exactly).
///
/// The API resolves streams server-side and hands back a direct URL. That
/// URL is what the player opens - no provider page, no ad script, no popup
/// ever loads inside the app.
class ScraperApi {
  ScraperApi(this.baseUrl, {http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String baseUrl;
  final http.Client _client;
  final bool _ownsClient;

  Future<List<VideoProvider>> getProviders() async {
    try {
      final uri = _endpoint('/providers');
      final response = await _get(uri);
      final body = _decodeObject(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300 || body['success'] != true) {
        throw ScraperApiException(_messageFrom(body, response.statusCode));
      }

      final providers = body['providers'];
      if (providers is! List) return const [];
      return providers
          .whereType<Map>()
          .map((provider) => Map<String, dynamic>.from(provider))
          .where((provider) => provider['enabled'] == true)
          .map(
            (provider) => VideoProvider.scraper(
              id: provider['id']?.toString() ?? '',
              name: provider['name']?.toString() ?? 'Unknown provider',
              alias: provider['alias']?.toString(),
              content: provider['content']?.toString(),
            ),
          )
          .where((provider) => provider.apiId?.isNotEmpty == true)
          .toList(growable: false);
    } finally {
      if (_ownsClient) _client.close();
    }
  }

  /// Returns ARKVideoScrapper's latest background provider-health snapshot.
  /// This endpoint is read-only: it never launches a costly health run from
  /// a viewer's device.
  Future<ProviderHealthSnapshot> getProviderHealthStatus() async {
    try {
      final response = await _get(_endpoint('/providers/status'));
      final body = _decodeObject(response.body);
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          body['success'] != true) {
        throw ScraperApiException(_messageFrom(body, response.statusCode));
      }
      return ProviderHealthSnapshot.fromJson(body);
    } finally {
      if (_ownsClient) _client.close();
    }
  }

  /// Requests a fresh, single-provider server check after an explicit user
  /// tap in the status screen. The scraper coalesces duplicate checks and
  /// applies its own short cooldown.
  Future<ProviderHealthResult> checkProviderHealth(String providerId) async {
    try {
      final encodedId = Uri.encodeComponent(providerId);
      final response = await _get(
        _endpoint('/providers/$encodedId/health-check'),
        timeout: const Duration(minutes: 2),
      );
      final body = _decodeObject(response.body);
      final rawProvider = body['provider'];
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          body['success'] != true ||
          rawProvider is! Map) {
        throw ScraperApiException(_messageFrom(body, response.statusCode));
      }
      return ProviderHealthResult.fromJson(
        Map<String, dynamic>.from(rawProvider),
      );
    } finally {
      if (_ownsClient) _client.close();
    }
  }

  /// Starts (or joins) the server's manually requested full provider scan.
  /// This is intentionally used only by the user pressing Refresh; ordinary
  /// screen loads read the lightweight cached snapshot above.
  Future<ProviderHealthSnapshot> checkAllProviderHealth() async {
    try {
      final response = await _get(
        _endpoint('/providers/health/check'),
        timeout: const Duration(minutes: 5),
      );
      final body = _decodeObject(response.body);
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          body['success'] != true) {
        throw ScraperApiException(_messageFrom(body, response.statusCode));
      }
      return ProviderHealthSnapshot.fromJson(body);
    } finally {
      if (_ownsClient) _client.close();
    }
  }

  Future<ProviderLoadResult> loadMovie({
    required String providerId,
    required int movieId,
  }) {
    return _loadStream('/stream-movie', {
      'provider': providerId,
      'tmdbId': '$movieId',
    });
  }

  Future<ProviderLoadResult> loadTVEpisode({
    required String providerId,
    required int tvId,
    required int seasonNumber,
    required int episodeNumber,
  }) {
    return _loadStream('/stream-tv', {
      'provider': providerId,
      'tmdbId': '$tvId',
      'season': '$seasonNumber',
      'episode': '$episodeNumber',
    });
  }

  Future<ProviderLoadResult> _loadStream(String path, Map<String, String> queryParameters) async {
    try {
      final uri = _endpoint(path, queryParameters);
      final response = await _get(uri, timeout: const Duration(minutes: 1));
      final body = _decodeObject(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300 || body['success'] != true) {
        return ProviderLoadResult(errorMessage: _messageFrom(body, response.statusCode));
      }

      final links = <RegularVideoLinks>[];
      final subtitles = <RegularSubtitleLinks>[];
      final seenSubtitles = <String>{};
      final rawLinks = body['links'];
      if (rawLinks is List) {
        for (final rawLink in rawLinks.whereType<Map>()) {
          final link = Map<String, dynamic>.from(rawLink);
          final url = link['url']?.toString();
          if (url == null || url.isEmpty) continue;
          final linkHeaders = _parseHeaders(link['headers']);
          links.add(RegularVideoLinks(
            url: url,
            quality: link['quality']?.toString() ?? 'unknown quality',
            server: link['server']?.toString(),
            isM3U8: link['isM3U8'] == true,
            isDash: link['isDASH'] == true,
            headers: linkHeaders,
            sizeToken: link['sizeToken']?.toString(),
          ));

          final rawSubtitles = link['subtitles'];
          if (rawSubtitles is List) {
            for (final rawSubtitle in rawSubtitles.whereType<Map>()) {
              final subtitle = Map<String, dynamic>.from(rawSubtitle);
              final file = subtitle['file']?.toString();
              if (file == null || file.isEmpty) continue;
              final language = subtitle['label']?.toString() ?? 'Unknown';
              if (seenSubtitles.add('$file $language')) {
                subtitles.add(RegularSubtitleLinks(
                  url: file,
                  language: language,
                  headers: _parseHeaders(subtitle['headers']) ?? linkHeaders,
                ));
              }
            }
          }
        }
      }

      if (links.isEmpty) {
        return ProviderLoadResult(errorMessage: _messageFrom(body, response.statusCode));
      }
      // HLS (.m3u8) sources seek reliably - the player just jumps to a
      // different segment file. A direct/progressive file link only seeks
      // cleanly if the origin CDN honours HTTP Range requests properly,
      // which a lot of these scraped hosts don't - that mismatch is what
      // causes a seek to hang forever or silently restart from 0:00. So
      // whenever a provider offers both kinds, play the HLS one by default;
      // direct links stay available in the quality/server switcher.
      final orderedLinks = [
        ...links.where((link) => link.isM3U8 == true),
        ...links.where((link) => link.isM3U8 != true),
      ];
      return ProviderLoadResult(success: true, videoLinks: orderedLinks, subtitleLinks: subtitles);
    } on TimeoutException {
      return const ProviderLoadResult(errorMessage: 'Scraper request timed out');
    } catch (error) {
      return ProviderLoadResult(errorMessage: error.toString());
    } finally {
      if (_ownsClient) _client.close();
    }
  }

  Future<http.Response> _get(Uri uri, {Duration timeout = const Duration(seconds: 30)}) {
    return _client.get(uri).timeout(timeout);
  }

  Uri _endpoint(String path, [Map<String, String>? queryParameters]) {
    final normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (normalized.isEmpty) {
      throw const ScraperApiException('Scraper API URL is not configured');
    }
    final root = normalized.endsWith('/api/v2') ? normalized : '$normalized/api/v2';
    return Uri.parse('$root$path').replace(queryParameters: queryParameters);
  }

  Map<String, dynamic> _decodeObject(String text) {
    try {
      final value = jsonDecode(text);
      return value is Map<String, dynamic> ? value : const {};
    } on FormatException {
      return const {};
    }
  }

  Map<String, String>? _parseHeaders(Object? value) {
    if (value is! Map) return null;
    final headers = <String, String>{};
    for (final entry in value.entries) {
      if (entry.value is String) headers[entry.key.toString()] = entry.value as String;
    }
    return headers.isEmpty ? null : headers;
  }

  String _messageFrom(Map<String, dynamic> body, int statusCode) {
    final error = body['error']?.toString();
    if (error != null && error.isNotEmpty) return error;
    final details = body['details']?.toString();
    if (details != null && details.isNotEmpty) return details;
    return 'Scraper request failed (HTTP $statusCode)';
  }
}

class ScraperApiException implements Exception {
  const ScraperApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ProviderHealthSnapshot {
  const ProviderHealthSnapshot({
    required this.updatedAt,
    required this.interval,
    required this.total,
    required this.online,
    required this.offline,
    required this.providers,
  });

  factory ProviderHealthSnapshot.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] is Map
        ? Map<String, dynamic>.from(json['summary'] as Map)
        : const <String, dynamic>{};
    final providers = (json['providers'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => ProviderHealthResult.fromJson(
            Map<String, dynamic>.from(item)))
        .where((provider) => provider.id.isNotEmpty)
        .toList(growable: false);
    int number(Object? value, int fallback) =>
        value is num ? value.toInt() : fallback;
    return ProviderHealthSnapshot(
      updatedAt: json['updatedAt'] is String
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
      interval: Duration(milliseconds: number(json['intervalMs'], 0)),
      total: number(summary['total'], providers.length),
      online: number(
        summary['online'],
        providers.where((provider) => provider.isOnline).length,
      ),
      offline: number(
        summary['offline'],
        providers.where((provider) => provider.isOffline).length,
      ),
      providers: providers,
    );
  }

  final DateTime? updatedAt;
  final Duration interval;
  final int total;
  final int online;
  final int offline;
  final List<ProviderHealthResult> providers;
}

class ProviderHealthResult {
  const ProviderHealthResult({
    required this.id,
    required this.alias,
    required this.status,
    required this.requestTime,
  });

  factory ProviderHealthResult.fromJson(Map<String, dynamic> json) {
    return ProviderHealthResult(
      id: json['id']?.toString() ?? '',
      alias: json['alias']?.toString() ?? '',
      status: json['status']?.toString() ?? 'untested',
      requestTime: Duration(
        milliseconds: json['requestTimeMs'] is num
            ? (json['requestTimeMs'] as num).toInt()
            : 0,
      ),
    );
  }

  final String id;
  final String alias;
  final String status;
  final Duration requestTime;

  bool get isOnline => status == 'online';
  bool get isOffline => status == 'offline';
  String get displayName => alias.trim().isEmpty ? id : alias;
}
