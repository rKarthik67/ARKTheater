import 'package:dio/dio.dart';
import '../core/config.dart';
import '../models/media_item.dart';
import '../models/live_tv_channel.dart';
import '../models/resolved_stream.dart';

/// Thin client for ARKVideoScrapper. This is the ONLY place the app talks to
/// the scraper — every screen that wants to play something goes through
/// here and gets back a ready-to-play, ad-free direct stream URL.
class ScraperService {
  ScraperService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: AppConfig.scraperBaseUrl,
              connectTimeout: const Duration(seconds: 15),
              // Scraping drives a real headless browser server-side, so this
              // can legitimately take several seconds.
              receiveTimeout: const Duration(seconds: 45),
            ));

  final Dio _dio;

  Future<List<LiveTvChannel>> liveTvChannels() async {
    final res = await _dio.get('/api/v2/live-tv/channels');
    final data = res.data as Map;
    if (data['success'] != true || data['channels'] is! List) {
      throw Exception(data['error'] ?? 'Could not load live TV channels.');
    }
    return (data['channels'] as List)
        .whereType<Map>()
        .map((entry) => LiveTvChannel.fromJson(Map<String, dynamic>.from(entry)))
        .toList();
  }

  Future<StreamResolution> resolveMovie(int tmdbId, {bool forceRefresh = false}) async {
    final res = await _dio.get(
      '/api/movie/$tmdbId',
      queryParameters: forceRefresh ? {'refresh': 1} : null,
    );
    return StreamResolution.fromJson(res.data as Map<String, dynamic>);
  }

  Future<StreamResolution> resolveTvEpisode(
    int tmdbId,
    int season,
    int episode, {
    bool forceRefresh = false,
  }) async {
    final res = await _dio.get(
      '/api/tv/$tmdbId/$season/$episode',
      queryParameters: forceRefresh ? {'refresh': 1} : null,
    );
    return StreamResolution.fromJson(res.data as Map<String, dynamic>);
  }

  Future<StreamResolution> resolve(
    MediaType type,
    int tmdbId, {
    int? season,
    int? episode,
    bool forceRefresh = false,
  }) {
    if (type == MediaType.movie) {
      return resolveMovie(tmdbId, forceRefresh: forceRefresh);
    }
    assert(season != null && episode != null, 'season/episode required for TV');
    return resolveTvEpisode(tmdbId, season!, episode!, forceRefresh: forceRefresh);
  }
}
