/// A subtitle result from Wyzie Subs (https://sub.wyzie.io) - ported from
/// flixquest's `ExternalSubtitle` model. Unlike `RegularSubtitleLinks` (which
/// only ever contains what the *current* scraped provider happened to embed),
/// this is fetched independently by TMDB id/season/episode, so it's available
/// no matter which provider ends up winning the race.
class ExternalSubtitle {
  ExternalSubtitle({
    required this.id,
    required this.url,
    required this.flagUrl,
    required this.format,
    required this.display,
    required this.language,
    required this.isHearingImpaired,
    required this.source,
    required this.downloadCount,
  });

  factory ExternalSubtitle.fromJson(Map<String, dynamic> json) {
    return ExternalSubtitle(
      id: json['id']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      flagUrl: json['flagUrl']?.toString() ?? '',
      format: json['format']?.toString() ?? 'srt',
      display: json['display']?.toString() ?? 'Unknown',
      language: json['language']?.toString() ?? 'en',
      isHearingImpaired: json['isHearingImpaired'] == true,
      source: json['source']?.toString() ?? 'wyzie',
      // Wyzie has no "rating" field, but downloadCount (how many times this
      // exact file has been downloaded on its source platform) is the
      // closest available proxy for "other people found this one correct" -
      // used to sort results so the most-downloaded (and so most likely
      // well-synced/accurate) subtitle shows first.
      downloadCount: (json['downloadCount'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String url;
  final String flagUrl;
  final String format;
  final String display;
  final String language;
  final bool isHearingImpaired;
  final String source;
  final int downloadCount;

  String get displayName => isHearingImpaired ? '$display (HI)' : display;
}
