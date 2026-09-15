import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central place every screen/service reads runtime config from. Values come
/// from `.env` (see `.env.example`) so API keys / base URLs are never
/// hardcoded into source that gets committed.
class AppConfig {
  AppConfig._();

  static String get tmdbApiKey =>
      dotenv.env['TMDB_API_KEY'] ?? '';

  static String get scraperBaseUrl =>
      (dotenv.env['SCRAPER_BASE_URL'] ?? 'https://ark-video-scrapper.vercel.app').replaceAll(
        RegExp(r'/+$'),
        '',
      );

  // Used to search sub.wyzie.io directly from the app for a title's
  // subtitles, independent of whichever scraped provider ends up
  // playing - see ExternalSubtitleService. Same free key you got from
  // https://store.wyzie.io/redeem for ARKVideoScrapper's .env; put it
  // here too (or share one WYZIE_SUBS_API_KEY value between both .env
  // files if you keep them in sync).
  static String get wyzieApiKey => dotenv.env['WYZIE_SUBS_API_KEY'] ?? '';

  static const String tmdbImageBase = 'https://image.tmdb.org/t/p';
}
