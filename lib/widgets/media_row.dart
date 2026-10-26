import 'package:flutter/material.dart';
import '../core/responsive.dart';
import '../core/app_fonts.dart';
import '../core/theme.dart';
import '../models/media_item.dart';
import 'fade_in_on_scroll.dart';
import 'media_card.dart';

/// Horizontal, swipeable rail of poster cards - used for "Trending",
/// "Popular", "Top Rated", "Similar Titles", etc. Card width adapts so the
/// same row looks right on a phone or a wide desktop window.
class MediaRow extends StatelessWidget {
  const MediaRow({
    super.key,
    required this.title,
    required this.items,
    required this.onItemTap,
    this.onViewMore,
    this.onItemRemove,
    this.ranked = false,
  });

  final String title;
  final List<MediaItem> items;
  final void Function(MediaItem) onItemTap;

  /// When set, shows a "View more" button next to the row title - mirrors
  /// the reference ARKPlay web app's per-section "View more" link, pushing
  /// a full paginated browse screen for that section instead of just the
  /// preview row.
  final VoidCallback? onViewMore;

  /// When set, every card in this row gets a small remove ("x") button -
  /// used by rows a title can be individually removed from (Home's
  /// "Recently Watched" row), left off everywhere else.
  final void Function(MediaItem)? onItemRemove;

  /// Gives a trending rail the large outlined rank treatment used by ranked
  /// streaming rows. The data remains the existing TMDB trending order.
  final bool ranked;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final columns = Responsive.gridColumns(context);
    final cardWidth = 1 / columns * (MediaQuery.sizeOf(context).width - 32) - 8;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The row's title sweeps in from the accent color and lifts into
          // place as the row scrolls into view (Settings > Motion turns
          // this off app-wide).
          FadeInOnScroll(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppTheme.resolvedStyle(context, AppTheme.sectionHeaderStyle, TextCategory.header),
                  ),
                ),
                if (onViewMore != null)
                  TextButton(
                    onPressed: onViewMore,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('View more'),
                  ),
              ],
            ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: cardWidth * 1.5 + 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = items[index];
                final width = cardWidth.clamp(110, 220).toDouble();
                final card = SizedBox(
                  width: width,
                  child: MediaCard(
                    item: item,
                    onTap: () => onItemTap(item),
                    onRemove: onItemRemove == null ? null : () => onItemRemove!(item),
                  ),
                );
                if (!ranked) return card;
                return SizedBox(
                  width: width + 28,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        bottom: 31,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 76,
                            height: 0.9,
                            fontWeight: FontWeight.w900,
                            foreground: Paint()
                              ..style = PaintingStyle.stroke
                              ..strokeWidth = 2
                              ..color = AppTheme.resolvedAccent(context),
                          ),
                        ),
                      ),
                      Positioned(left: 26, top: 0, child: card),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
