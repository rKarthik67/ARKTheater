import 'package:flutter/material.dart';
import '../core/responsive.dart';
import '../core/theme.dart';
import '../models/media_item.dart';
import 'error_view.dart';
import 'loading_indicator.dart';
import 'media_card.dart';

/// Generic infinite-scroll paginated poster grid - powers every "browse
/// deeply" surface in the app (genre grids, language grids, the Platforms
/// feature's OTT-provider/production-house results, and every "View more"
/// destination) through a single `fetchPage` callback instead of one
/// bespoke widget per data source.
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
  final _scrollController = ScrollController();
  int _page = 0;
  int _totalPages = 1;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadNextPage();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final threshold = _scrollController.position.maxScrollExtent - 600;
    if (_scrollController.position.pixels >= threshold) _loadNextPage();
  }

  Future<void> _loadNextPage() async {
    if (_loadingMore || (_page > 0 && _page >= _totalPages)) return;
    setState(() {
      if (_page == 0) {
        _loading = true;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final result = await widget.fetchPage(_page + 1);
      if (!mounted) return;
      setState(() {
        _items.addAll(result.items);
        _page += 1;
        _totalPages = result.totalPages;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
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
    if (_error != null && _items.isEmpty) {
      return ErrorView(
        message: 'Could not load titles.\n$_error',
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
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: 0.56,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: _items.length + (_page < _totalPages ? columns : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.accent));
        }
        final item = _items[index];
        return MediaCard(item: item, onTap: () => widget.onSelect(item));
      },
    );
  }
}
