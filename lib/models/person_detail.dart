import 'media_item.dart';

/// A cast/crew member's full profile plus their filmography, for the
/// "tap a cast member" detail screen.
class PersonDetail {
  final int id;
  final String name;
  final String? biography;
  final String? profilePath;
  final String? birthday;
  final String? placeOfBirth;
  final List<MediaItem> knownFor;

  const PersonDetail({
    required this.id,
    required this.name,
    this.biography,
    this.profilePath,
    this.birthday,
    this.placeOfBirth,
    this.knownFor = const [],
  });

  String? profileUrl({String size = 'w300'}) =>
      profilePath == null ? null : 'https://image.tmdb.org/t/p/$size$profilePath';
}

/// Lightweight person-search result - just enough for a search results
/// list tile. Tapping one opens the full PersonDetailScreen, which fetches
/// everything else (bio, filmography) via TmdbService.personDetails.
class PersonSummary {
  final int id;
  final String name;
  final String? profilePath;

  const PersonSummary({required this.id, required this.name, this.profilePath});

  factory PersonSummary.fromJson(Map<String, dynamic> json) => PersonSummary(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        profilePath: json['profile_path'] as String?,
      );

  String? profileUrl({String size = 'w200'}) =>
      profilePath == null ? null : 'https://image.tmdb.org/t/p/$size$profilePath';
}
