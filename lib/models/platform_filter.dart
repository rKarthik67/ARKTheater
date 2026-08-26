/// Which TMDB `/discover` filter a [PlatformFilter] maps to - a streaming
/// service uses `with_watch_providers`, a studio uses `with_companies`.
enum PlatformFilterType { provider, company }

class PlatformFilter {
  final String name;
  final int id;

  /// Wikimedia Commons logo URL, where the reference web app had one on
  /// file - rendered via flutter_svg by lib/widgets/platform_logo.dart.
  /// Platforms without one fall back to a TMDB `logo_path` fetched at
  /// runtime (see TmdbService.watchProviderLogos/companyLogoPath).
  final String? commonsLogo;

  const PlatformFilter({required this.name, required this.id, this.commonsLogo});
}

/// OTT platforms to browse by, with their TMDB watch-provider IDs - ported
/// verbatim from the reference ARKPlay web app's `platformFilters.js`.
const kOttPlatforms = <PlatformFilter>[
  PlatformFilter(name: 'Prime Video', id: 119, commonsLogo: 'https://upload.wikimedia.org/wikipedia/commons/1/11/Amazon_Prime_Video_logo.svg'),
  PlatformFilter(name: 'Netflix', id: 8, commonsLogo: 'https://upload.wikimedia.org/wikipedia/commons/0/08/Netflix_2015_logo.svg'),
  PlatformFilter(name: 'Hulu', id: 15, commonsLogo: 'https://upload.wikimedia.org/wikipedia/commons/f/f9/Hulu_logo_%282018%29.svg'),
  PlatformFilter(name: 'Disney+ Hotstar', id: 122, commonsLogo: 'https://upload.wikimedia.org/wikipedia/commons/1/1e/Disney%2B_Hotstar_logo.svg'),
  PlatformFilter(name: 'Disney+', id: 337, commonsLogo: 'https://upload.wikimedia.org/wikipedia/commons/3/3e/Disney%2B_logo.svg'),
  PlatformFilter(name: 'Paramount+', id: 531, commonsLogo: 'https://upload.wikimedia.org/wikipedia/commons/4/4e/Paramount%2B_logo.svg'),
  PlatformFilter(name: 'Apple TV+', id: 350, commonsLogo: 'https://upload.wikimedia.org/wikipedia/commons/2/28/Apple_TV_Plus_Logo.svg'),
  PlatformFilter(name: 'Max', id: 1899, commonsLogo: 'https://upload.wikimedia.org/wikipedia/commons/7/7e/HBO_Max_May_2025_%28Horizontal%29.svg'),
  PlatformFilter(name: 'Peacock', id: 386),
  PlatformFilter(name: 'discovery+', id: 520, commonsLogo: 'https://upload.wikimedia.org/wikipedia/commons/6/61/Discovery_Plus_logo.svg'),
  PlatformFilter(name: 'Tubi', id: 73, commonsLogo: 'https://upload.wikimedia.org/wikipedia/commons/d/db/Tubi_logo.svg'),
  PlatformFilter(name: 'Pluto TV', id: 300, commonsLogo: 'https://upload.wikimedia.org/wikipedia/commons/5/5d/Pluto_TV_logo.svg'),
  PlatformFilter(name: 'Rakuten TV', id: 35),
  PlatformFilter(name: 'ZEE5', id: 232),
  PlatformFilter(name: 'Sony LIV', id: 237),
  PlatformFilter(name: 'MUBI', id: 11),
  PlatformFilter(name: 'Crunchyroll', id: 283, commonsLogo: 'https://upload.wikimedia.org/wikipedia/commons/d/d9/Crunchyroll_2024.svg'),
  PlatformFilter(name: 'Sun Nxt', id: 309),
  PlatformFilter(name: 'Viki', id: 160),
  PlatformFilter(name: 'AMC+', id: 528),
  PlatformFilter(name: 'STARZ', id: 318),
  PlatformFilter(name: 'YouTube Premium', id: 188, commonsLogo: 'https://upload.wikimedia.org/wikipedia/commons/d/dd/YouTube_Premium_logo.svg'),
  PlatformFilter(name: 'Shudder', id: 99),
  PlatformFilter(name: 'Curiosity Stream', id: 190),
  PlatformFilter(name: 'Fandor', id: 25),
  PlatformFilter(name: 'MX Player', id: 381),
  PlatformFilter(name: 'aha', id: 1116, commonsLogo: 'https://upload.wikimedia.org/wikipedia/commons/b/b3/Aha_OTT_Logo.svg'),
  PlatformFilter(name: 'Lionsgate Play', id: 273),
  PlatformFilter(name: 'BINGE', id: 385, commonsLogo: 'https://upload.wikimedia.org/wikipedia/commons/f/ff/Binge_logo.svg'),
  PlatformFilter(name: 'Stan', id: 356),
];

/// Production houses / studios to browse by, with their TMDB company IDs -
/// ported verbatim from the reference ARKPlay web app's `platformFilters.js`.
const kProductionHouses = <PlatformFilter>[
  PlatformFilter(name: 'Warner Bros.', id: 174),
  PlatformFilter(name: 'Paramount Pictures', id: 4),
  PlatformFilter(name: 'Walt Disney Pictures', id: 2),
  PlatformFilter(name: 'Universal Pictures', id: 33),
  PlatformFilter(name: '20th Century Studios', id: 25),
  PlatformFilter(name: 'Marvel Studios', id: 420),
  PlatformFilter(name: 'DC Entertainment', id: 9993),
  PlatformFilter(name: 'Blumhouse Productions', id: 3172),
  PlatformFilter(name: 'A24', id: 41077),
  PlatformFilter(name: 'Lionsgate', id: 1632),
  PlatformFilter(name: 'Pixar', id: 3),
  PlatformFilter(name: 'DreamWorks Animation', id: 521),
  PlatformFilter(name: 'Legendary Pictures', id: 923),
  PlatformFilter(name: 'Columbia Pictures', id: 5, commonsLogo: 'https://upload.wikimedia.org/wikipedia/commons/1/18/Columbia_Pictures_logo_%281975%E2%80%931981%29.svg'),
  PlatformFilter(name: 'Illumination', id: 6704),
  PlatformFilter(name: 'New Line Cinema', id: 12),
  PlatformFilter(name: 'StudioCanal', id: 694),
  PlatformFilter(name: 'Focus Features', id: 10146),
  PlatformFilter(name: 'Annapurna Pictures', id: 10342),
  PlatformFilter(name: 'Bad Robot', id: 11461, commonsLogo: 'https://upload.wikimedia.org/wikipedia/commons/b/bf/Bad_Robot_Productions.svg'),
  PlatformFilter(name: 'Sony Pictures', id: 34),
  PlatformFilter(name: 'Metro-Goldwyn-Mayer', id: 8411),
  PlatformFilter(name: 'Miramax', id: 53009),
  PlatformFilter(name: 'Skydance Media', id: 82819),
  PlatformFilter(name: 'Plan B Entertainment', id: 81),
  PlatformFilter(name: 'Regency Enterprises', id: 508),
  PlatformFilter(name: 'Village Roadshow Pictures', id: 79),
  PlatformFilter(name: 'Scott Free Productions', id: 1645),
  PlatformFilter(name: 'Working Title Films', id: 10163),
];

PlatformFilter? getPlatformFilter(PlatformFilterType type, int id) {
  final list = type == PlatformFilterType.provider ? kOttPlatforms : kProductionHouses;
  for (final filter in list) {
    if (filter.id == id) return filter;
  }
  return null;
}
