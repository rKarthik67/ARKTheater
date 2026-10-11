import 'media_item.dart';

class CastMember {
  final int id;
  final String name;
  final String? profilePath;

  const CastMember({required this.id, required this.name, this.profilePath});

  factory CastMember.fromJson(Map<String, dynamic> json) => CastMember(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        profilePath: json['profile_path'] as String?,
      );
}

class SeasonSummary {
  final int seasonNumber;
  final String name;
  final int episodeCount;
  final String? posterPath;

  const SeasonSummary({
    required this.seasonNumber,
    required this.name,
    required this.episodeCount,
    this.posterPath,
  });

  factory SeasonSummary.fromJson(Map<String, dynamic> json) => SeasonSummary(
        seasonNumber: json['season_number'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        episodeCount: json['episode_count'] as int? ?? 0,
        posterPath: json['poster_path'] as String?,
      );

  String? posterUrl({String size = 'w300'}) =>
      posterPath == null ? null : 'https://image.tmdb.org/t/p/$size$posterPath';
}

/// One episode within a season - powers the episode-card picker on
/// DetailScreen (poster-style, mirrors the reference web app's episode
/// Swiper) instead of a plain "E1"/"E2" button row.
class EpisodeSummary {
  final int episodeNumber;
  final String name;
  final String? stillPath;
  final String? overview;

  const EpisodeSummary({
    required this.episodeNumber,
    required this.name,
    this.stillPath,
    this.overview,
  });

  factory EpisodeSummary.fromJson(Map<String, dynamic> json) => EpisodeSummary(
        episodeNumber: json['episode_number'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        stillPath: json['still_path'] as String?,
        overview: json['overview'] as String?,
      );

  String? stillUrl({String size = 'w300'}) =>
      stillPath == null ? null : 'https://image.tmdb.org/t/p/$size$stillPath';
}

/// Full detail payload for a movie/tv show detail screen.
class MediaDetail {
  final MediaItem item;
  final List<String> genres;
  final int? runtimeMinutes;
  final List<CastMember> cast;
  /// Official TMDB collection/franchise parts. TMDB currently exposes this
  /// relationship for movies; TV relationships can be supplied here when a
  /// reliable source is available instead of guessing from title text.
  final String? collectionName;
  final List<MediaItem> collectionItems;
  final List<MediaItem> similar;
  final List<SeasonSummary> seasons; // empty for movies

  const MediaDetail({
    required this.item,
    this.genres = const [],
    this.runtimeMinutes,
    this.cast = const [],
    this.collectionName,
    this.collectionItems = const [],
    this.similar = const [],
    this.seasons = const [],
  });
}
