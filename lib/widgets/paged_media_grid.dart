import 'package:flutter/material.dart';
import '../core/responsive.dart';
import '../core/theme.dart';
import '../models/media_item.dart';
import 'error_view.dart';
import 'fade_in_on_scroll.dart';
import 'loading_indicator.dart';
import 'media_card.dart';

/// Generic paginated poster grid - powers every "browse deeply" surface in
/// the app (genre grids, language grids, the Platforms feature's
/// OTT-provider/production-house results, and every "View more"
/// destination) through a single `fetchPage` callback instead of one
/// bespoke widget per data source.
///
/// Loads one TMDB page (20 titles) on open so the first screenful paints
/// fast, then pulls [_kMoreCount] more each time the user taps "Load
/// more" - deliberately NOT auto-fetching on scroll. That used to be scroll-triggered, but a failed "load next page"
/// request left the grid stuck on a permanent spinner with no way to
/// retry (nothing re-triggered the fetch unless the user scrolled away and
/// back). A tap-triggered load makes each fetch a single deliberate
/// request instead of a burst, and failures get a visible error + Retry
/// button right where the tap was, instead of failing silently.
class PagedMediaGrid extends StatefulWidget {
  const PagedMediaGrid({
    super.key,
    required this.fetchPage,
    required this.onSelect,
  });

  /// Fetches one 1-indexed page of results.
  final Future<({List<MediaItem> items, int totalPages})> Function(int page) fetchPage;
  final void Function(MediaItem) onSelect;

  @override
  State<PagedMediaGrid> createState() => _PagedMediaGridState();
}

/// How many titles the first paint shows - one TMDB page exactly, so
/// opening a grid costs a single request.
const _kInitialCount = 20;

/// How many each "Load more" tap adds. TMDB pages are 20 at a time, so
/// this spans multiple requests and leaves a remainder, which
/// [_PagedMediaGridState._buffer] carries into the next tap - that keeps
/// every tap worth exactly this many titles instead of drifting to 60.
const _kMoreCount = 50;

class _PagedMediaGridState extends State<PagedMediaGrid> {
  final _items = <MediaItem>[];

  /// Fetched from TMDB but not yet shown: the leftover when a batch's size
  /// isn't a whole number of 20-item pages.
  final _buffer = <MediaItem>[];
  int _page = 0;
  int _totalPages = 1;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _initialError;
  Object? _moreError;

  @override
  void initState() {
    super.initState();
    _loadNextBatch(wanted: _kInitialCount);
  }

  /// True while there's anything left to show - either already fetched and
  /// waiting in [_buffer], or another TMDB page to ask for.
  bool get _hasMore => _buffer.isNotEmpty || _page < _totalPages;

  Future<void> _loadNextBatch({required int wanted}) async {
    if (_loadingMore || (_page > 0 && !_hasMore)) return;
    setState(() {
      if (_page == 0) {
        _loading = true;
        _initialError = null;
      } else {
        _loadingMore = true;
        _moreError = null;
      }
    });
    try {
      final batch = <MediaItem>[];
      // Serve from the buffer first, then fetch whole pages until the
      // batch is full (or TMDB runs out). Requests go one at a time rather
      // than in parallel - the same reasoning as Home's bounded
      // concurrency: bursting requests on a shared api_key is what made
      // rows intermittently fail to load.
      while (batch.length < wanted && (_buffer.isNotEmpty || _page < _totalPages)) {
        if (_buffer.isNotEmpty) {
          final take = wanted - batch.length;
          final slice = _buffer.take(take).toList();
          batch.addAll(slice);
          _buffer.removeRange(0, slice.length);
          continue;
        }
        final result = await widget.fetchPage(_page + 1);
        if (!mounted) return;
        _page += 1;
        _totalPages = result.totalPages;
        _buffer.addAll(result.items);
      }
      if (!mounted) return;
      setState(() => _items.addAll(batch));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (_items.isEmpty) {
          _initialError = error;
        } else {
          _moreError = error;
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingIndicator();
    if (_initialError != null && _items.isEmpty) {
      return ErrorView(
        message: 'Could not load titles.\n$_initialError',
        onRetry: () => setState(() {
          _page = 0;
          _buffer.clear();
          _loadNextBatch(wanted: _kInitialCount);
        }),
      );
    }
    if (_items.isEmpty) {
      return Center(child: Text('No results', style: TextStyle(color: AppTheme.textSecondaryOf(context))));
    }

    final columns = Responsive.gridColumns(context);
    final hasMore = _hasMore;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: 0.56,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = _items[index];
                return FadeInOnScroll(
                  colorSweep: false,
                  delay: Duration(milliseconds: 30 * (index % 8)),
                  child: MediaCard(item: item, onTap: () => widget.onSelect(item)),
                );
              },
              childCount: _items.length,
            ),
          ),
        ),
        if (hasMore || _loadingMore || _moreError != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator(color: AppTheme.accent)
                    : _moreError != null
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Could not load more titles.',
                                style: TextStyle(color: AppTheme.textSecondaryOf(context)),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton(
                                onPressed: () => _loadNextBatch(wanted: _kMoreCount),
                                child: const Text('Retry'),
                              ),
                            ],
                          )
                        : OutlinedButton(
                            onPressed: () => _loadNextBatch(wanted: _kMoreCount),
                            child: const Text('Load $_kMoreCount more'),
                          ),
              ),
            ),
          ),
        // Keeps the "Load more" button (or the final row of posters, once
        // everything is loaded) clear of the floating nav bar, which is
        // painted over this scroll view and would otherwise swallow the
        // tap. See Responsive.bottomNavInset.
        SliverToBoxAdapter(
          child: SizedBox(height: Responsive.bottomNavInset(context)),
        ),
      ],
    );
  }
}
