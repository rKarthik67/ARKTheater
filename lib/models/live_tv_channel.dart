class LiveTvChannel {
  const LiveTvChannel({
    required this.id,
    required this.name,
    required this.country,
    required this.language,
    required this.category,
    required this.url,
    required this.isHls,
    this.logo,
  });

  final String id;
  final String name;
  final String country;
  final String language;
  final String category;
  final String url;
  final bool isHls;
  final String? logo;

  factory LiveTvChannel.fromJson(Map<String, dynamic> json) => LiveTvChannel(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Untitled channel',
        country: json['country'] as String? ?? 'Worldwide',
        language: json['language'] as String? ?? 'Other',
        category: json['category'] as String? ?? 'Other',
        url: json['url'] as String? ?? '',
        isHls: json['isHls'] == true,
        logo: json['logo'] as String?,
      );
}
