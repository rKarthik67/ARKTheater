import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/responsive.dart';
import '../core/theme.dart';
import '../models/media_item.dart';
import '../models/person_detail.dart';
import '../services/tmdb_service.dart';
import '../widgets/error_view.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/media_card.dart';

/// Cast/crew member profile: photo, bio, and every movie/TV show they've
/// worked on (tapping one opens that title's own DetailScreen via
/// `onSelectTitle`, forwarded from wherever this screen was opened from).
///
/// Movies and TV shows are shown as two separate, independently scrollable
/// tabs rather than one combined horizontal "Known For" slider - a slider
/// only ever shows a handful of titles at a glance and is awkward to work
/// through for a prolific actor/director, whereas a vertically scrollable
/// grid per media type lets every credit actually be browsed.
class PersonDetailScreen extends StatefulWidget {
  const PersonDetailScreen({
    super.key,
    required this.personId,
    required this.personName,
    required this.onSelectTitle,
  });

  final int personId;
  final String personName;
  final void Function(MediaItem) onSelectTitle;

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen>
    with SingleTickerProviderStateMixin {
  final _tmdb = TmdbService();
  late Future<PersonDetail> _future;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _future = _tmdb.personDetails(widget.personId);
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.personName)),
      body: FutureBuilder<PersonDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingIndicator(label: 'Loading...');
          }
          if (snapshot.hasError) {
            return ErrorView(message: 'Failed to load cast details.\n${snapshot.error}');
          }
          final person = snapshot.data!;
          // person.knownFor is TMDB's combined_credits (movie + TV) already
          // fetched in one go by TmdbService.personDetails - split it by
          // type here rather than issuing two more network calls.
          final movies = person.knownFor.where((i) => i.type == MediaType.movie).toList();
          final tvShows = person.knownFor.where((i) => i.type == MediaType.tv).toList();

          return NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 110,
                              height: 150,
                              child: person.profileUrl() != null
                                  ? CachedNetworkImage(
                                      imageUrl: person.profileUrl()!,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      color: AppTheme.surfaceVariantOf(context),
                                      child: Icon(
                                        Icons.person_outline,
                                        color: AppTheme.textSecondaryOf(context),
                                        size: 40,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(person.name, style: Theme.of(context).textTheme.headlineSmall),
                                const SizedBox(height: 8),
                                if (person.birthday != null)
                                  Text(
                                    'Born: ${person.birthday}',
                                    style: TextStyle(color: AppTheme.textSecondaryOf(context)),
                                  ),
                                if (person.placeOfBirth != null)
                                  Text(
                                    person.placeOfBirth!,
                                    style: TextStyle(color: AppTheme.textSecondaryOf(context)),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (person.biography != null) ...[
                        const SizedBox(height: 20),
                        Text('Biography', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          person.biography!,
                          style: TextStyle(color: AppTheme.textSecondaryOf(context)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (person.knownFor.isNotEmpty)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarHeaderDelegate(
                    TabBar(
                      controller: _tabController,
                      labelColor: AppTheme.resolvedAccent(context),
                      unselectedLabelColor: AppTheme.textSecondaryOf(context),
                      indicatorColor: AppTheme.resolvedAccent(context),
                      tabs: [
                        Tab(text: 'Movies (${movies.length})'),
                        Tab(text: 'TV Shows (${tvShows.length})'),
                      ],
                    ),
                  ),
                ),
            ],
            body: person.knownFor.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No filmography found.',
                        style: TextStyle(color: AppTheme.textSecondaryOf(context)),
                      ),
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _FilmographyGrid(
                        items: movies,
                        emptyLabel: 'No movies found.',
                        onItemTap: widget.onSelectTitle,
                      ),
                      _FilmographyGrid(
                        items: tvShows,
                        emptyLabel: 'No TV shows found.',
                        onItemTap: widget.onSelectTitle,
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

/// Pins the tab bar itself (not the whole header) below the profile/bio
/// section as the user scrolls - `NestedScrollView`'s standard
/// `SliverPersistentHeader` wrapper for a `TabBar`.
class _TabBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  _TabBarHeaderDelegate(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(color: AppTheme.backgroundOf(context), child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _TabBarHeaderDelegate oldDelegate) => oldDelegate.tabBar != tabBar;
}

/// One tab's worth of filmography - a plain vertically-scrollable poster
/// grid (same card style/columns as every other browse grid in the app),
/// not a slider, since every item here is already in hand from
/// combined_credits and there's no pagination to drive.
class _FilmographyGrid extends StatelessWidget {
  const _FilmographyGrid({
    required this.items,
    required this.emptyLabel,
    required this.onItemTap,
  });

  final List<MediaItem> items;
  final String emptyLabel;
  final void Function(MediaItem) onItemTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(emptyLabel, style: TextStyle(color: AppTheme.textSecondaryOf(context))),
      );
    }
    final columns = Responsive.gridColumns(context);
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: 0.56,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return MediaCard(item: item, onTap: () => onItemTap(item));
      },
    );
  }
}
