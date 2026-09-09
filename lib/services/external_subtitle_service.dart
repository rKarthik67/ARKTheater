import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../models/external_subtitle.dart';

/// Client for Wyzie Subs (https://sub.wyzie.io) - ported from flixquest's
/// `ExternalSubtitleService`. This is called directly from the app with the
/// user's own free key (see AppConfig.wyzieApiKey / the WYZIE_SUBS_API_KEY
/// entry in .env), independent of ARKVideoScrapper - so subtitles are
/// available even for providers that don't embed their own, and even if the
/// scraper's own Wyzie fallback isn't configured.
class ExternalSubtitleService {
  static const String _baseUrl = 'https://sub.wyzie.io';

  static Future<List<ExternalSubtitle>> fetchMovieSubtitles(int tmdbId) {
    return _search({'id': '$tmdbId'});
  }

  static Future<List<ExternalSubtitle>> fetchTVSubtitles(
    int tmdbId,
    int seasonNumber,
    int episodeNumber,
  ) {
    return _search({
      'id': '$tmdbId',
      'season': '$seasonNumber',
      'episode': '$episodeNumber',
    });
  }

  static Future<List<ExternalSubtitle>> _search(Map<String, String> query) async {
    final key = AppConfig.wyzieApiKey;
    if (key.isEmpty) return const [];

    final uri = Uri.parse('$_baseUrl/search').replace(
      queryParameters: {...query, 'key': key},
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      // Include the response body (Wyzie returns a short JSON/text reason
      // for 401s, etc.) so a broken key or a Wyzie-side policy change shows
      // up as something readable instead of a bare status code.
      final bodyPreview = response.body.length > 200 ? '${response.body.substring(0, 200)}...' : response.body;
      throw Exception('Wyzie Subs request failed (HTTP ${response.statusCode}): $bodyPreview');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    final subtitles = decoded
        .whereType<Map>()
        .map((json) => ExternalSubtitle.fromJson(Map<String, dynamic>.from(json)))
        .toList();
    // English first (it's what most users want by default), ranked among
    // itself by downloadCount - Wyzie has no quality/rating field, so
    // downloadCount (most downloaded first) is the closest available signal
    // for "other people found this one correct": a subtitle with a bad
    // sync or wrong episode rarely accumulates many downloads. Every other
    // language follows after, also ranked by downloadCount among itself.
    int rank(ExternalSubtitle s) => s.language.toLowerCase() == 'en' ? 0 : 1;
    subtitles.sort((a, b) {
      final byLanguage = rank(a).compareTo(rank(b));
      if (byLanguage != 0) return byLanguage;
      return b.downloadCount.compareTo(a.downloadCount);
    });
    return subtitles;
  }
}
