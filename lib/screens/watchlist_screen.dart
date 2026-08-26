import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/responsive.dart';
import '../core/theme.dart';
import '../models/media_item.dart';
import '../state/watchlist_provider.dart';
import '../widgets/media_card.dart';

class WatchlistScreen extends StatelessWidget {
  const WatchlistScreen({super.key, required this.onSelect});

  final void Function(MediaItem) onSelect;

  @override
  Widget build(BuildContext context) {
    final watchlist = context.watch<WatchlistProvider>();
    final items = watchlist.items;

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
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: Responsive.gridColumns(context),
                    childAspectRatio: 0.56,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return MediaCard(item: item, onTap: () => onSelect(item));
                  },
                ),
    );
  }
}
