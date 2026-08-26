import 'common.dart';
import 'names.dart';
import 'scraper_api.dart';
import 'vixsrc.dart';

typedef ProviderResultCallback = void Function(
  int index,
  VideoProvider provider,
  ProviderLoadResult result,
);

class ProviderSelection {
  const ProviderSelection({
    required this.index,
    required this.provider,
    required this.result,
  });

  final int index;
  final VideoProvider provider;
  final ProviderLoadResult result;
}

/// Single loading boundary for direct and scraper-API-backed providers -
/// ported from flixquest's `ProviderLoader`.
///
/// Starts providers in groups of three while resolving their results in
/// the configured order: a fast lower-priority result is held until every
/// provider before it has failed, and the next group only starts once the
/// current group has produced no playable result. This is what lets the
/// app auto-recover from a dead/slow provider without the user ever
/// noticing, while still preferring providers earlier in the list.
abstract final class ProviderLoader {
  static Future<ProviderSelection?> loadFirstSuccessful({
    required List<VideoProvider> providers,
    required Future<ProviderLoadResult> Function(VideoProvider provider) load,
    ProviderResultCallback? onResult,
  }) async {
    for (var batchStart = 0; batchStart < providers.length; batchStart += 3) {
      final batchEnd = (batchStart + 3 < providers.length) ? batchStart + 3 : providers.length;
      final requests = <Future<ProviderLoadResult>>[];

      for (var index = batchStart; index < batchEnd; index++) {
        final provider = providers[index];
        final request = () async {
          ProviderLoadResult result;
          try {
            result = await load(provider);
          } catch (error) {
            result = ProviderLoadResult(errorMessage: error.toString());
          }
          onResult?.call(index, provider, result);
          return result;
        }();
        requests.add(request);
      }

      for (var offset = 0; offset < requests.length; offset++) {
        final result = await requests[offset];
        if (result.success && (result.videoLinks?.isNotEmpty ?? false)) {
          final index = batchStart + offset;
          return ProviderSelection(index: index, provider: providers[index], result: result);
        }
      }
    }
    return null;
  }

  static Future<ProviderLoadResult> loadMovieFromProvider({
    required VideoProvider provider,
    required int movieId,
    required String scraperApiUrl,
  }) {
    switch (provider.type) {
      case VideoProviderType.directVixSrc:
        return VixSrc.loadMovie(movieId);
      case VideoProviderType.scraperApi:
        final providerId = provider.apiId;
        if (providerId == null || providerId.isEmpty) {
          return Future.value(const ProviderLoadResult(errorMessage: 'Provider ID is missing'));
        }
        return ScraperApi(scraperApiUrl).loadMovie(providerId: providerId, movieId: movieId);
    }
  }

  static Future<ProviderLoadResult> loadTVFromProvider({
    required VideoProvider provider,
    required int tvId,
    required int seasonNumber,
    required int episodeNumber,
    required String scraperApiUrl,
  }) {
    switch (provider.type) {
      case VideoProviderType.directVixSrc:
        return VixSrc.loadEpisode(
          tvId: tvId,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
        );
      case VideoProviderType.scraperApi:
        final providerId = provider.apiId;
        if (providerId == null || providerId.isEmpty) {
          return Future.value(const ProviderLoadResult(errorMessage: 'Provider ID is missing'));
        }
        return ScraperApi(scraperApiUrl).loadTVEpisode(
          providerId: providerId,
          tvId: tvId,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
        );
    }
  }
}
