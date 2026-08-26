import 'package:dio/dio.dart';
import '../core/config.dart';
import '../models/media_detail.dart';
import '../models/genre.dart';
import '../models/media_item.dart';
import '../models/person_detail.dart';

/// All read-only browse/search/detail metadata comes from TMDB directly —
/// same as the reference ARKPlay web app's `src/api.js` + `MovieDetail.js`.
/// Only the actual video stream is resolved through ARKVideoScrapper.
class TmdbService {
  TmdbService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://api.themoviedb.org/3',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ));

  final Dio _dio;

  Map<String, dynamic> get _auth => {'api_key': AppConfig.tmdbApiKey};

  Future<List<MediaItem>> trending(MediaType type) async {
    final path = type == MediaType.movie ? '/trending/movie/week' : '/trending/tv/week';
    final res = await _dio.get(path, queryParameters: _auth);
    return _mapResults(res.data, type);
  }

  Future<List<MediaItem>> popular(MediaType type) async {
    final path = type == MediaType.movie ? '/movie/popular' : '/tv/popular';
    final res = await _dio.get(path, queryParameters: _auth);
    return _mapResults(res.data, type);
  }

  Future<List<MediaItem>> topRated(MediaType type) async {
    final path = type == MediaType.movie ? '/movie/top_rated' : '/tv/top_rated';
    final res = await _dio.get(path, queryParameters: _auth);
    return _mapResults(res.data, type);
  }

  Future<List<MediaItem>> nowPlaying() async {
    final res = await _dio.get('/movie/now_playing', queryParameters: _auth);
    return _mapResults(res.data, MediaType.movie);
  }

  /// Paginated twin of [trending] - powers the "View more" destination for
  /// that row instead of just the preview list.
  Future<({List<MediaItem> items, int totalPages})> trendingPaged(
    MediaType type, {
    int page = 1,
  }) async {
    final path = type == MediaType.movie ? '/trending/movie/week' : '/trending/tv/week';
    final res = await _dio.get(path, queryParameters: {..._auth, 'page': page});
    return (items: _mapResults(res.data, type), totalPages: _totalPages(res.data));
  }

  /// Paginated twin of [popular].
  Future<({List<MediaItem> items, int totalPages})> popularPaged(
    MediaType type, {
    int page = 1,
  }) async {
    final path = type == MediaType.movie ? '/movie/popular' : '/tv/popular';
    final res = await _dio.get(path, queryParameters: {..._auth, 'page': page});
    return (items: _mapResults(res.data, type), totalPages: _totalPages(res.data));
  }

  /// Paginated twin of [topRated].
  Future<({List<MediaItem> items, int totalPages})> topRatedPaged(
    MediaType type, {
    int page = 1,
  }) async {
    final path = type == MediaType.movie ? '/movie/top_rated' : '/tv/top_rated';
    final res = await _dio.get(path, queryParameters: {..._auth, 'page': page});
    return (items: _mapResults(res.data, type), totalPages: _totalPages(res.data));
  }

  /// Paginated twin of [nowPlaying] (movies only - TMDB has no TV
  /// "now playing" endpoint).
  Future<({List<MediaItem> items, int totalPages})> nowPlayingPaged({int page = 1}) async {
    final res = await _dio.get('/movie/now_playing', queryParameters: {..._auth, 'page': page});
    return (items: _mapResults(res.data, MediaType.movie), totalPages: _totalPages(res.data));
  }

  /// Combined movie+TV title search - superseded by [searchMovies]/
  /// [searchTV] for the Search screen (which needs per-type results to
  /// filter/tab independently), kept for anything that wants a single
  /// mixed list.
  Future<List<MediaItem>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final res = await _dio.get(
      '/search/multi',
      queryParameters: {..._auth, 'query': query, 'include_adult': false},
    );
    final results = (res.data['results'] as List? ?? []);
    return results
        .where((r) => r['media_type'] == 'movie' || r['media_type'] == 'tv')
        .map((r) {
          final type = r['media_type'] == 'movie' ? MediaType.movie : MediaType.tv;
          return MediaItem.fromTmdbJson(r as Map<String, dynamic>, type);
        })
        .toList();
  }

  /// Title search scoped to movies - powers the Search screen's Movies tab.
  Future<List<MediaItem>> searchMovies(String query, {int page = 1}) async {
    if (query.trim().isEmpty) return [];
    final res = await _dio.get('/search/movie', queryParameters: {
      ..._auth,
      'query': query,
      'include_adult': false,
      'page': page,
    });
    return _mapResults(res.data, MediaType.movie);
  }

  /// Title search scoped to TV shows - powers the Search screen's TV tab.
  Future<List<MediaItem>> searchTV(String query, {int page = 1}) async {
    if (query.trim().isEmpty) return [];
    final res = await _dio.get('/search/tv', queryParameters: {
      ..._auth,
      'query': query,
      'include_adult': false,
      'page': page,
    });
    return _mapResults(res.data, MediaType.tv);
  }

  /// Person search - powers the Search screen's People tab.
  Future<List<PersonSummary>> searchPeople(String query, {int page = 1}) async {
    if (query.trim().isEmpty) return [];
    final res = await _dio.get('/search/person', queryParameters: {
      ..._auth,
      'query': query,
      'include_adult': false,
      'page': page,
    });
    final results = (res.data['results'] as List? ?? []);
    return results.map((p) => PersonSummary.fromJson(p as Map<String, dynamic>)).toList();
  }

  /// A TV show's total season count - only fetched on demand (e.g. the
  /// Search screen's season-count filter), since it needs a full /tv/{id}
  /// call that list endpoints don't include.
  Future<int?> tvSeasonCount(int tvId) async {
    try {
      final res = await _dio.get('/tv/$tvId', queryParameters: _auth);
      return (res.data['number_of_seasons'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  /// The best available YouTube trailer key for a title - powers the Home
  /// hero banner's "Trailer" button, mirroring the reference ARKPlay web
  /// app's HeroSlide trailer modal.
  Future<String?> trailerYoutubeKey(MediaType type, int id) async {
    final path = type == MediaType.movie ? '/movie/$id/videos' : '/tv/$id/videos';
    final res = await _dio.get(path, queryParameters: _auth);
    final results = (res.data['results'] as List? ?? []).cast<Map<String, dynamic>>();
    if (results.isEmpty) return null;
    final trailer = results.firstWhere(
      (v) => v['site'] == 'YouTube' && v['type'] == 'Trailer',
      orElse: () => results.firstWhere((v) => v['site'] == 'YouTube', orElse: () => const {}),
    );
    return trailer['key'] as String?;
  }

  Future<MediaDetail> details(int id, MediaType type) async {
    final path = type == MediaType.movie ? '/movie/$id' : '/tv/$id';
    final results = await Future.wait([
      _dio.get(path, queryParameters: _auth),
      _dio.get('$path/credits', queryParameters: _auth),
      _dio.get('$path/similar', queryParameters: _auth),
    ]);

    final detailsJson = results[0].data as Map<String, dynamic>;
    final creditsJson = results[1].data as Map<String, dynamic>;
    final similarJson = results[2].data as Map<String, dynamic>;

    final item = MediaItem.fromTmdbJson(detailsJson, type);
    final genres = (detailsJson['genres'] as List? ?? [])
        .map((g) => g['name'] as String)
        .toList();
    final runtime = type == MediaType.movie
        ? detailsJson['runtime'] as int?
        : (detailsJson['episode_run_time'] as List?)?.cast<int>().firstOrNull;
    final cast = (creditsJson['cast'] as List? ?? [])
        .take(12)
        .map((c) => CastMember.fromJson(c as Map<String, dynamic>))
        .toList();
    final similar = (similarJson['results'] as List? ?? [])
        .map((s) => MediaItem.fromTmdbJson(s as Map<String, dynamic>, type))
        .toList();
    final seasons = type == MediaType.tv
        ? (detailsJson['seasons'] as List? ?? [])
            .map((s) => SeasonSummary.fromJson(s as Map<String, dynamic>))
            .where((s) => s.seasonNumber > 0)
            .toList()
        : <SeasonSummary>[];

    return MediaDetail(
      item: item,
      genres: genres,
      runtimeMinutes: runtime,
      cast: cast,
      similar: similar,
      seasons: seasons,
    );
  }

  /// Episodes for one season - powers the poster-style episode picker on
  /// DetailScreen, mirroring the reference web app's `fetchEpisodes`.
  Future<List<EpisodeSummary>> episodes(int tvId, int seasonNumber) async {
    final res = await _dio.get('/tv/$tvId/season/$seasonNumber', queryParameters: _auth);
    final episodes = (res.data['episodes'] as List? ?? []);
    return episodes
        .map((e) => EpisodeSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Genre list for filter chips - movie and TV genre IDs differ (e.g.
  /// Action is 28 for movies, "Action & Adventure" is 10759 for TV), so
  /// this is fetched per media type.
  Future<List<Genre>> genres(MediaType type) async {
    final path = type == MediaType.movie ? '/genre/movie/list' : '/genre/tv/list';
    final res = await _dio.get(path, queryParameters: _auth);
    final list = (res.data['genres'] as List? ?? []);
    return list.map((g) => Genre.fromJson(g as Map<String, dynamic>)).toList();
  }

  /// One language's titles, most popular first - powers Home's per-language
  /// rows (Tamil/Telugu/Kannada/Malayalam/Hindi/Korean/Japanese/English),
  /// the same `discover/{movie,tv}?with_original_language=` pattern the
  /// reference ARKPlay web app's Home.js uses for its language rows,
  /// extended here to cover TV shows too (the reference only did movies).
  Future<List<MediaItem>> discoverByLanguage(MediaType type, String languageCode) async {
    final result = await discover(type, languageCode: languageCode);
    return result.items;
  }

  /// General-purpose TMDB `/discover` call - the one place every filtered
  /// browse surface in the app goes through (the Movies/TV Shows tabs'
  /// genre+language+year filters, and the Platforms feature's OTT-provider
  /// / production-house results). Filters are additive: pass as many as
  /// apply and TMDB ANDs them together.
  Future<({List<MediaItem> items, int totalPages})> discover(
    MediaType type, {
    int? genreId,
    String? languageCode,
    int? watchProviderId,
    int? companyId,
    int? year,
    String watchRegion = 'IN',
    int page = 1,
    String sortBy = 'popularity.desc',
  }) async {
    final path = type == MediaType.movie ? '/discover/movie' : '/discover/tv';
    final params = <String, dynamic>{
      ..._auth,
      'sort_by': sortBy,
      'page': page,
      'include_adult': false,
    };
    if (genreId != null) params['with_genres'] = genreId;
    if (languageCode != null) params['with_original_language'] = languageCode;
    if (watchProviderId != null) {
      params['with_watch_providers'] = watchProviderId;
      params['watch_region'] = watchRegion;
      params['with_watch_monetization_types'] = 'flatrate';
    }
    if (companyId != null) params['with_companies'] = companyId;
    if (year != null) {
      params[type == MediaType.movie ? 'primary_release_year' : 'first_air_date_year'] = year;
    }

    final res = await _dio.get(path, queryParameters: params);
    return (items: _mapResults(res.data, type), totalPages: _totalPages(res.data));
  }

  List<MediaItem> _mapResults(dynamic data, MediaType type) {
    final results = (data['results'] as List? ?? []);
    return results
        .map((r) => MediaItem.fromTmdbJson(r as Map<String, dynamic>, type))
        .toList();
  }

  int _totalPages(dynamic data) => (data['total_pages'] as num?)?.toInt() ?? 1;

  /// Maps every TMDB movie watch-provider ID to its `logo_path`, in one
  /// request - same endpoint the reference web app's Platforms.js calls to
  /// resolve logos for [kOttPlatforms]. Entries with no commonsLogo fall
  /// back to this.
  Future<Map<int, String>> watchProviderLogos() async {
    final res = await _dio.get('/watch/providers/movie', queryParameters: _auth);
    final results = (res.data['results'] as List?) ?? const [];
    return {
      for (final entry in results)
        if (entry['provider_id'] != null && entry['logo_path'] != null)
          entry['provider_id'] as int: entry['logo_path'] as String,
    };
  }

  /// A single production company's `logo_path`, or null if TMDB has none
  /// on file / the lookup fails - called once per [kProductionHouses] entry
  /// without a commonsLogo, mirroring Platforms.js's per-company fetch.
  Future<String?> companyLogoPath(int companyId) async {
    try {
      final res = await _dio.get('/company/$companyId', queryParameters: _auth);
      return res.data['logo_path'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Full profile + filmography for a cast/crew member - powers the "tap a
  /// cast member" screen, mirroring the reference web app's PersonDetail.js.
  Future<PersonDetail> personDetails(int personId) async {
    final results = await Future.wait([
      _dio.get('/person/$personId', queryParameters: _auth),
      _dio.get('/person/$personId/combined_credits', queryParameters: _auth),
    ]);

    final personJson = results[0].data as Map<String, dynamic>;
    final creditsJson = results[1].data as Map<String, dynamic>;

    final castCredits = (creditsJson['cast'] as List? ?? []);
    final knownFor = castCredits
        .where((c) => c['media_type'] == 'movie' || c['media_type'] == 'tv')
        .map((c) {
          final type = c['media_type'] == 'movie' ? MediaType.movie : MediaType.tv;
          return MediaItem.fromTmdbJson(c as Map<String, dynamic>, type);
        })
        .toList()
      ..sort((a, b) => b.voteAverage.compareTo(a.voteAverage));

    // combined_credits can list the same title twice (different character
    // credits on the same show/movie) - de-dupe by type+id before showing it.
    final seen = <String>{};
    final dedupedKnownFor = <MediaItem>[];
    for (final item in knownFor) {
      final key = '${item.type}:${item.id}';
      if (seen.add(key)) dedupedKnownFor.add(item);
    }

    final biography = personJson['biography'] as String?;

    return PersonDetail(
      id: personJson['id'] as int,
      name: personJson['name'] as String? ?? '',
      biography: (biography == null || biography.trim().isEmpty) ? null : biography,
      profilePath: personJson['profile_path'] as String?,
      birthday: personJson['birthday'] as String?,
      placeOfBirth: personJson['place_of_birth'] as String?,
      knownFor: dedupedKnownFor,
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
