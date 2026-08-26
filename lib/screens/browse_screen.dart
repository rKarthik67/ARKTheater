import 'package:flutter/material.dart';
import '../models/media_item.dart';
import '../widgets/paged_media_grid.dart';

/// Full-page paginated destination for a single home-screen section's
/// "View more" link - mirrors the reference ARKPlay web app's dedicated
/// browse routes (`/movies`, `/tamil-movies`, `/tvshows`, etc.), done here
/// as one reusable screen parameterized by a `fetchPage` callback instead
/// of one route per section.
class BrowseScreen extends StatelessWidget {
  const BrowseScreen({
    super.key,
    required this.title,
    required this.fetchPage,
    required this.onSelect,
  });

  final String title;
  final Future<({List<MediaItem> items, int totalPages})> Function(int page) fetchPage;
  final void Function(MediaItem) onSelect;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PagedMediaGrid(fetchPage: fetchPage, onSelect: onSelect),
    );
  }
}
