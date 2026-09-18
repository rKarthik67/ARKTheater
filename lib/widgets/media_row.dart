import 'package:flutter/material.dart';
import '../core/responsive.dart';
import '../core/app_fonts.dart';
import '../core/theme.dart';
import '../models/media_item.dart';
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
          Padding(
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
                return SizedBox(
                  width: cardWidth.clamp(110, 220),
                  child: MediaCard(
                    item: item,
                    onTap: () => onItemTap(item),
                    onRemove: onItemRemove == null ? null : () => onItemRemove!(item),
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
