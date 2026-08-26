/// Mirrors ARKVideoScrapper's `ResolvedStream` JSON shape. This is the only
/// thing the player ever sees — a clean, direct, ad-free URL plus whatever
/// headers the CDN requires. No iframe, no provider page, no ad script ever
/// reaches the app.
class ResolvedStream {
  final String provider;
  final String url;
  final String kind; // hls | mp4 | dash
  final String? quality;
  final Map<String, String> headers;
  final List<SubtitleTrackInfo> subtitles;

  const ResolvedStream({
    required this.provider,
    required this.url,
    required this.kind,
    this.quality,
    this.headers = const {},
    this.subtitles = const [],
  });

  factory ResolvedStream.fromJson(Map<String, dynamic> json) => ResolvedStream(
        provider: json['provider'] as String? ?? 'Unknown',
        url: json['url'] as String,
        kind: json['kind'] as String? ?? 'hls',
        quality: json['quality'] as String?,
        headers: (json['headers'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            ) ??
            const {},
        subtitles: (json['subtitles'] as List? ?? [])
            .map((e) => SubtitleTrackInfo.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class SubtitleTrackInfo {
  final String lang;
  final String label;
  final String url;

  const SubtitleTrackInfo({required this.lang, required this.label, required this.url});

  factory SubtitleTrackInfo.fromJson(Map<String, dynamic> json) => SubtitleTrackInfo(
        lang: json['lang'] as String? ?? 'en',
        label: json['label'] as String? ?? 'Subtitle',
        url: json['url'] as String,
      );
}

class StreamResolution {
  final String? title;
  final bool cached;
  final List<ResolvedStream> streams;

  const StreamResolution({this.title, this.cached = false, this.streams = const []});

  factory StreamResolution.fromJson(Map<String, dynamic> json) => StreamResolution(
        title: json['title'] as String?,
        cached: json['cached'] as bool? ?? false,
        streams: (json['streams'] as List? ?? [])
            .map((e) => ResolvedStream.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  bool get hasPlayableStream => streams.isNotEmpty;
}
