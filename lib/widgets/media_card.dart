import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/media_item.dart';
import '../state/watchlist_provider.dart';

class MediaCard extends StatelessWidget {
  const MediaCard({super.key, required this.item, required this.onTap, this.onRemove});

  final MediaItem item;
  final VoidCallback onTap;

  /// When set, shows a small "x" button in the poster's top-left corner -
  /// used by rows where a title can be individually removed (Home's
  /// "Recently Watched" row) rather than every row that uses MediaCard.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final posterUrl = item.posterUrl();
    // Bookmark icon on every poster, everywhere MediaCard is used - reads
    // straight from the same app-wide WatchlistProvider DetailScreen's own
    // bookmark button and the Watchlist tab already use, so toggling here
    // stays in sync with both.
    final watchlist = context.watch<WatchlistProvider>();
    final isBookmarked = watchlist.contains(item.type, item.id);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: posterUrl == null
                      ? Container(
                          color: AppTheme.surfaceVariant,
                          child: const Icon(Icons.movie_outlined, color: AppTheme.textSecondary),
                        )
                      : CachedNetworkImage(
                          imageUrl: posterUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: AppTheme.surfaceVariant),
                          errorWidget: (_, __, ___) => Container(
                            color: AppTheme.surfaceVariant,
                            child: const Icon(Icons.broken_image_outlined, color: AppTheme.textSecondary),
                          ),
                        ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: _PosterIconButton(
                    icon: isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                    color: isBookmarked ? AppTheme.accent : Colors.white,
                    onTap: () => context.read<WatchlistProvider>().toggle(item),
                  ),
                ),
                if (onRemove != null)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: _PosterIconButton(icon: Icons.close, color: Colors.white, onTap: onRemove!),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          if (item.year.isNotEmpty)
            Text(
              item.year,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

/// Small circular semi-transparent icon button overlaid on a poster - kept
/// tiny so it doesn't dominate the poster art. Its own Material/InkWell
/// intercepts the tap before it reaches the card's outer InkWell.
class _PosterIconButton extends StatelessWidget {
  const _PosterIconButton({required this.icon, required this.color, required this.onTap});

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}
