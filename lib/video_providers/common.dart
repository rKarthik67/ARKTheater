/// Shared result shapes for every stream provider (scraper-API-backed or
/// direct), ported from flixquest's `lib/video_providers/common.dart` so the
/// player and provider loader can treat every source identically regardless
/// of where it came from.
class RegularVideoLinks {
  String? url;
  String? quality;
  String? server;
  bool? isM3U8;
  bool? isDash;
  Map<String, String>? headers;
  String? sizeToken;

  RegularVideoLinks({
    this.url,
    this.quality = 'unknown quality',
    this.server,
    this.isM3U8,
    this.isDash,
    this.headers,
    this.sizeToken,
  });

  RegularVideoLinks.fromJson(Map<String, dynamic> json) {
    url = json['url'] as String?;
    server = json['server']?.toString();
    quality = json.containsKey('quality') ? json['quality'] as String? : 'unknown quality';
    isM3U8 = json['isM3U8'] as bool?;
    isDash = json['isDASH'] as bool?;
    sizeToken = json['sizeToken']?.toString();
    final rawHeaders = json['headers'];
    if (rawHeaders is Map) {
      headers = {
        for (final entry in rawHeaders.entries)
          if (entry.value is String) entry.key.toString(): entry.value as String,
      };
    }
  }
}

class RegularSubtitleLinks {
  String? url;
  String? language;
  Map<String, String>? headers;

  RegularSubtitleLinks({this.language, this.url, this.headers});

  RegularSubtitleLinks.fromJson(Map<String, dynamic> json) {
    url = (json['url'] ?? json['file']) as String?;
    language = (json['lang'] ?? json['label']) as String?;
    final rawHeaders = json['headers'];
    if (rawHeaders is Map) {
      headers = {
        for (final entry in rawHeaders.entries)
          if (entry.value is String) entry.key.toString(): entry.value as String,
      };
    }
  }
}

/// The normalized result returned by every in-app stream provider - direct
/// (VixSrc) or scraper-API-backed alike - so the player and DetailScreen
/// use one contract regardless of source.
class ProviderLoadResult {
  const ProviderLoadResult({
    this.videoLinks,
    this.subtitleLinks,
    this.success = false,
    this.errorMessage,
  });

  final List<RegularVideoLinks>? videoLinks;
  final List<RegularSubtitleLinks>? subtitleLinks;
  final bool success;
  final String? errorMessage;
}
