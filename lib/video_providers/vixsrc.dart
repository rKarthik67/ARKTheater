import 'package:http/http.dart' as http;

import 'common.dart';

/// Direct fallback provider - ported (simplified) from flixquest's
/// `VixSrc` client. Talks to vixsrc.to's own JSON API straight from the
/// app, with no ARKVideoScrapper involved, so playback still works even if
/// the scraper backend is down or unreachable.
abstract final class VixSrc {
  static const String _baseUrl = 'https://vixsrc.to';

  static Future<ProviderLoadResult> loadMovie(int movieId) {
    return _load('$_baseUrl/movie/$movieId');
  }

  static Future<ProviderLoadResult> loadEpisode({
    required int tvId,
    required int seasonNumber,
    required int episodeNumber,
  }) {
    if (seasonNumber <= 0) {
      return Future.value(const ProviderLoadResult(errorMessage: 'Invalid season number'));
    }
    return _load('$_baseUrl/tv/$tvId/$seasonNumber/$episodeNumber');
  }

  static Future<ProviderLoadResult> _load(String pageUrl) async {
    try {
      final pageRes = await http
          .get(Uri.parse(pageUrl), headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 20));
      if (pageRes.statusCode != 200) {
        return ProviderLoadResult(errorMessage: 'VixSrc page HTTP ${pageRes.statusCode}');
      }

      // The embed page bootstraps a JS `window.masterPlaylist` object with
      // the token/expires query params needed to hit the real .m3u8 - this
      // regex mirrors what the page's own player script reads.
      final tokenMatch = RegExp(r"""'token':\s*'([a-zA-Z0-9]+)'""").firstMatch(pageRes.body);
      final expiresMatch = RegExp(r"""'expires':\s*'(\d+)'""").firstMatch(pageRes.body);
      final urlMatch = RegExp(r"""url:\s*'([^']+)'""").firstMatch(pageRes.body);
      if (tokenMatch == null || expiresMatch == null || urlMatch == null) {
        return const ProviderLoadResult(errorMessage: 'VixSrc playlist metadata not found');
      }

      final base = urlMatch.group(1)!;
      final token = tokenMatch.group(1)!;
      final expires = expiresMatch.group(1)!;
      final separator = base.contains('?') ? '&' : '?';
      final playlistUrl = '$base${separator}token=$token&expires=$expires&h=1&lang=en';

      return ProviderLoadResult(
        success: true,
        videoLinks: [
          RegularVideoLinks(
            url: playlistUrl,
            quality: 'auto',
            server: 'VixSrc',
            isM3U8: true,
            headers: const {'User-Agent': _userAgent, 'Referer': _baseUrl},
          ),
        ],
        subtitleLinks: const [],
      );
    } catch (error) {
      return ProviderLoadResult(errorMessage: error.toString());
    }
  }

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';
}
