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
/// Loads the first 20 (one TMDB page) on open, then only fetches the next
/// 20 when the user taps "Load more" - deliberately NOT auto-fetching on
/// scroll. That used to be scroll-triggered, but a failed "load next page"
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

class _PagedMediaGridState extends State<PagedMediaGrid> {
  final _items = <MediaItem>[];
  int _page = 0;
  int _totalPages = 1;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _initialError;
  Object? _moreError;

  @override
  void initState() {
    super.initState();
    _loadNextPage();
  }

  Future<void> _loadNextPage() async {
    if (_loadingMore || (_page > 0 && _page >= _totalPages)) return;
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
      final result = await widget.fetchPage(_page + 1);
      if (!mounted) return;
      setState(() {
        _items.addAll(result.items);
        _page += 1;
        _totalPages = result.totalPages;
      });
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
          _loadNextPage();
        }),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('No results', style: TextStyle(color: AppTheme.textSecondary)));
    }

    final columns = Responsive.gridColumns(context);
    final hasMore = _page < _totalPages;

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
                              const Text(
                                'Could not load more titles.',
                                style: TextStyle(color: AppTheme.textSecondary),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton(onPressed: _loadNextPage, child: const Text('Retry')),
                            ],
                          )
                        : OutlinedButton(
                            onPressed: _loadNextPage,
                            child: const Text('Load 20 more'),
                          ),
              ),
            ),
          ),
      ],
    );
  }
}
