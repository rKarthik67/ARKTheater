import '../core/config.dart';

enum MediaType { movie, tv }

/// Common shape shared by movies and TV shows, enough for browse grids,
/// carousels, and search results. Full detail (cast, seasons, similar
/// titles) is fetched lazily per-item on the detail screen.
class MediaItem {
  final int id;
  final MediaType type;
  final String title;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final double voteAverage;
  final String? releaseDate;

  /// The time this title entered a watchlist. It is supplied by the shared
  /// library and persisted locally so every device can use newest-first order.
  final DateTime? watchlistAddedAt;

  /// Device-local playback activity. It deliberately is not part of the
  /// shared-library merge contract: another device watching a title should
  /// not rearrange this device's personal watchlist view.
  final DateTime? watchlistLastWatchedAt;

  /// TMDB genre IDs and original-language code - present on every list-style
  /// TMDB response (discover/trending/popular/top_rated/search) and on
  /// detail responses too, so this is safe to leave empty/null when
  /// building a MediaItem from anywhere else (e.g. local storage). Used to
  /// client-side filter search results by genre/language, since TMDB's
  /// /search endpoints don't accept discover-style filter params.
  final List<int> genreIds;
  final String? originalLanguage;

  const MediaItem({
    required this.id,
    required this.type,
    required this.title,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.voteAverage = 0,
    this.releaseDate,
    this.watchlistAddedAt,
    this.watchlistLastWatchedAt,
    this.genreIds = const [],
    this.originalLanguage,
  });

  MediaItem withWatchlistAddedAt(DateTime addedAt) => MediaItem(
        id: id,
        type: type,
        title: title,
        overview: overview,
        posterPath: posterPath,
        backdropPath: backdropPath,
        voteAverage: voteAverage,
        releaseDate: releaseDate,
        genreIds: genreIds,
        originalLanguage: originalLanguage,
        watchlistAddedAt: addedAt,
        watchlistLastWatchedAt: watchlistLastWatchedAt,
      );

  MediaItem withWatchlistLastWatchedAt(DateTime watchedAt) => MediaItem(
        id: id,
        type: type,
        title: title,
        overview: overview,
        posterPath: posterPath,
        backdropPath: backdropPath,
        voteAverage: voteAverage,
        releaseDate: releaseDate,
        genreIds: genreIds,
        originalLanguage: originalLanguage,
        watchlistAddedAt: watchlistAddedAt,
        watchlistLastWatchedAt: watchedAt,
      );

  factory MediaItem.fromTmdbJson(Map<String, dynamic> json, MediaType type) {
    return MediaItem(
      id: json['id'] as int,
      type: type,
      title: (json['title'] ?? json['name'] ?? 'Untitled') as String,
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0,
      releaseDate: (json['release_date'] ?? json['first_air_date']) as String?,
      genreIds: (json['genre_ids'] as List?)?.cast<int>() ?? const [],
      originalLanguage: json['original_language'] as String?,
    );
  }

  String? posterUrl({String size = 'w500'}) =>
      posterPath == null ? null : '${AppConfig.tmdbImageBase}/$size$posterPath';

  String? backdropUrl({String size = 'original'}) =>
      backdropPath == null ? null : '${AppConfig.tmdbImageBase}/$size$backdropPath';

  String get year => (releaseDate != null && releaseDate!.length >= 4)
      ? releaseDate!.substring(0, 4)
      : '';
}
