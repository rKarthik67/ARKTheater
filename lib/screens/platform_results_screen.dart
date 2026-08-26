import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/media_item.dart';
import '../models/platform_filter.dart';
import '../services/tmdb_service.dart';
import '../widgets/paged_media_grid.dart';
import '../widgets/platform_logo.dart';

/// Paginated Movies/TV results for one OTT platform or production house -
/// mirrors the reference ARKPlay web app's `PlatformResults.js`, which
/// toggles between `with_watch_providers` and `with_companies` TMDB
/// `/discover` queries behind the same Movies/TV switch.
class PlatformResultsScreen extends StatefulWidget {
  const PlatformResultsScreen({
    super.key,
    required this.filter,
    required this.filterType,
    required this.watchRegion,
    required this.tmdb,
    required this.onSelect,
    this.tmdbLogoPath,
  });

  final PlatformFilter filter;
  final PlatformFilterType filterType;
  final String watchRegion;
  final TmdbService tmdb;
  final void Function(MediaItem) onSelect;

  /// Resolved once already by PlatformsScreen (which already fetched every
  /// provider/company logo for the browse cards) - passed straight through
  /// instead of re-fetching, so opening a result screen doesn't cost a
  /// second network round trip for a logo it already has.
  final String? tmdbLogoPath;

  @override
  State<PlatformResultsScreen> createState() => _PlatformResultsScreenState();
}

class _PlatformResultsScreenState extends State<PlatformResultsScreen> {
  MediaType _mediaType = MediaType.movie;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PlatformLogo(filter: widget.filter, tmdbLogoPath: widget.tmdbLogoPath, size: 36),
            const SizedBox(width: 10),
            Flexible(child: Text(widget.filter.name, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<MediaType>(
              segments: const [
                ButtonSegment(value: MediaType.movie, label: Text('Movies'), icon: Icon(Icons.movie_outlined)),
                ButtonSegment(value: MediaType.tv, label: Text('TV Shows'), icon: Icon(Icons.tv_outlined)),
              ],
              selected: {_mediaType},
              onSelectionChanged: (selection) => setState(() => _mediaType = selection.first),
              style: ButtonStyle(
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected) ? Colors.white : AppTheme.textSecondary,
                ),
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected) ? AppTheme.accent : AppTheme.surfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: PagedMediaGrid(
              key: ValueKey('${widget.filter.id}-$_mediaType'),
              fetchPage: (page) => widget.tmdb.discover(
                _mediaType,
                watchProviderId: widget.filterType == PlatformFilterType.provider ? widget.filter.id : null,
                companyId: widget.filterType == PlatformFilterType.company ? widget.filter.id : null,
                watchRegion: widget.watchRegion,
                page: page,
              ),
              onSelect: widget.onSelect,
            ),
          ),
        ],
      ),
    );
  }
}
