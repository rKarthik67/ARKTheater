import '../models/media_item.dart';

/// Embed-page URL builders for the WebView fallback (see
/// WebViewPlayerScreen) - used ONLY when every native provider in
/// video_providers/ fails. These render the provider's own page, the same
/// one the reference React web app puts directly in an <iframe>.
class EmbedProvider {
  const EmbedProvider({required this.name, required this.movieUrl, required this.tvUrl});

  final String name;
  final String Function(int tmdbId) movieUrl;
  final String Function(int tmdbId, int season, int episode) tvUrl;

  String urlFor(MediaType type, int tmdbId, {int? season, int? episode}) {
    if (type == MediaType.movie) return movieUrl(tmdbId);
    assert(season != null && episode != null, 'season/episode required for TV');
    return tvUrl(tmdbId, season!, episode!);
  }
}

const embedProviders = <EmbedProvider>[
  EmbedProvider(name: 'Videasy', movieUrl: _videasyMovie, tvUrl: _videasyTv),
  EmbedProvider(name: 'VidLink', movieUrl: _vidlinkMovie, tvUrl: _vidlinkTv),
  EmbedProvider(name: 'VidSrcMe', movieUrl: _vidsrcMeMovie, tvUrl: _vidsrcMeTv),
  EmbedProvider(name: 'VidCore', movieUrl: _vidcoreMovie, tvUrl: _vidcoreTv),
  EmbedProvider(name: 'Codeera', movieUrl: _codeeraMovie, tvUrl: _codeeraTv),
];

String _videasyMovie(int id) => 'https://player.videasy.net/movie/$id';
String _videasyTv(int id, int s, int e) => 'https://player.videasy.net/tv/$id/$s/$e';

String _vidlinkMovie(int id) => 'https://vidlink.pro/movie/$id';
String _vidlinkTv(int id, int s, int e) => 'https://vidlink.pro/tv/$id/$s/$e';

String _vidsrcMeMovie(int id) => 'https://vidsrcme.ru/embed/movie/$id';
String _vidsrcMeTv(int id, int s, int e) => 'https://vidsrcme.ru/embed/tv?tmdb=$id&season=$s&episode=$e';

String _vidcoreMovie(int id) => 'https://vidcore.org/embed/movie/$id';
String _vidcoreTv(int id, int s, int e) => 'https://vidcore.org/embed/tv/$id/$s/$e';

String _codeeraMovie(int id) => 'https://iembed.codeera.dev/embed/movie/$id';
String _codeeraTv(int id, int s, int e) => 'https://iembed.codeera.dev/embed/tv/$id/$s/$e';
