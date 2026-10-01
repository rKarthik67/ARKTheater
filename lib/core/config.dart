import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central place every screen/service reads runtime config from. Values come
/// from `.env` (see `.env.example`) so API keys / base URLs are never
/// hardcoded into source that gets committed.
class AppConfig {
  AppConfig._();

  static const String oracleScraperBaseUrl = 'http://129.154.245.13';
  static const String vercelScraperBaseUrl =
      'https://ark-video-scrapper.vercel.app';

  static String _scraperBaseUrl = oracleScraperBaseUrl;

  static String get tmdbApiKey =>
      dotenv.env['TMDB_API_KEY'] ?? '';

  /// The selected endpoint is loaded from [SettingsProvider] after launch.
  /// Only the two maintained endpoints are accepted here.
  static String get scraperBaseUrl => _scraperBaseUrl;

  /// Shared watchlists require the Oracle host where SQLite lives. This may be
  /// overridden with an HTTPS domain once one is configured; unlike streaming,
  /// a library credential must never be sent over an untrusted connection.
  static String get sharedWatchlistBaseUrl =>
      (dotenv.env['SHARED_WATCHLIST_BASE_URL'] ?? oracleScraperBaseUrl)
          .replaceAll(RegExp(r'/+$'), '');

  static void setScraperBaseUrl(String value) {
    final normalized = value.replaceAll(RegExp(r'/+$'), '');
    _scraperBaseUrl = normalized == vercelScraperBaseUrl
        ? vercelScraperBaseUrl
        : oracleScraperBaseUrl;
  }

  // Used to search sub.wyzie.io directly from the app for a title's
  // subtitles, independent of whichever scraped provider ends up
  // playing - see ExternalSubtitleService. Same free key you got from
  // https://store.wyzie.io/redeem for ARKVideoScrapper's .env; put it
  // here too (or share one WYZIE_SUBS_API_KEY value between both .env
  // files if you keep them in sync).
  static String get wyzieApiKey => dotenv.env['WYZIE_SUBS_API_KEY'] ?? '';

  static const String tmdbImageBase = 'https://image.tmdb.org/t/p';
}
