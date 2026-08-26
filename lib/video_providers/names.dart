/// Ported from flixquest's `video_providers/names.dart`.
enum VideoProviderType { directVixSrc, scraperApi }

class VideoProvider {
  const VideoProvider({
    required this.fullName,
    required this.codeName,
    this.alias,
    this.content,
    this.type = VideoProviderType.directVixSrc,
    this.apiId,
  });

  /// Provider name supplied by the service. Kept for diagnostics.
  final String fullName;

  /// A unique in-app identifier. Scraper IDs are namespaced so they cannot
  /// collide with a direct provider that happens to share an upstream ID.
  final String codeName;

  /// User-facing name (an alias, e.g. so a provider's real hostname is
  /// never shown to the user).
  final String? alias;

  /// Human-readable catalogue/language coverage supplied by the scraper.
  final String? content;
  final VideoProviderType type;
  final String? apiId;

  String get displayName {
    final value = alias?.trim();
    return value == null || value.isEmpty ? fullName : value;
  }

  static const directVixSrc = VideoProvider(
    fullName: 'VixSrc',
    alias: 'VixSrc Direct',
    codeName: 'direct:vixsrc',
    type: VideoProviderType.directVixSrc,
    apiId: 'vixsrc',
  );

  factory VideoProvider.scraper({
    required String id,
    required String name,
    String? alias,
    String? content,
  }) {
    return VideoProvider(
      fullName: name,
      alias: alias,
      content: content,
      codeName: 'scraper:$id',
      type: VideoProviderType.scraperApi,
      apiId: id,
    );
  }
}
