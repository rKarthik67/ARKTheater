import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/responsive.dart';
import '../core/theme.dart';
import '../models/media_item.dart';
import '../state/watchlist_provider.dart';
import '../widgets/media_card.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key, required this.onSelect});

  final void Function(MediaItem) onSelect;

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  MediaType _mediaType = MediaType.movie;

  @override
  Widget build(BuildContext context) {
    final watchlist = context.watch<WatchlistProvider>();
    final items = watchlist.items;
    final movies = items.where((i) => i.type == MediaType.movie).toList();
    final tvShows = items.where((i) => i.type == MediaType.tv).toList();
    final shown = _mediaType == MediaType.movie ? movies : tvShows;

    return Scaffold(
      appBar: AppBar(title: const Text('My Watchlist')),
      body: !watchlist.isLoaded
          ? const SizedBox.shrink()
          : items.isEmpty
              ? const Center(
                  child: Text(
                    'Titles you bookmark show up here.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: SegmentedButton<MediaType>(
                        segments: [
                          ButtonSegment(
                            value: MediaType.movie,
                            label: Text('Movies (${movies.length})'),
                            icon: const Icon(Icons.movie_outlined),
                          ),
                          ButtonSegment(
                            value: MediaType.tv,
                            label: Text('TV Shows (${tvShows.length})'),
                            icon: const Icon(Icons.tv_outlined),
                          ),
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
                      child: shown.isEmpty
                          ? Center(
                              child: Text(
                                _mediaType == MediaType.movie
                                    ? 'No movies in your watchlist yet.'
                                    : 'No TV shows in your watchlist yet.',
                                style: const TextStyle(color: AppTheme.textSecondary),
                              ),
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: Responsive.gridColumns(context),
                                childAspectRatio: 0.56,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 16,
                              ),
                              itemCount: shown.length,
                              itemBuilder: (context, index) {
                                final item = shown[index];
                                return MediaCard(item: item, onTap: () => widget.onSelect(item));
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
