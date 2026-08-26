import 'package:flutter/material.dart';
import '../models/media_item.dart';
import 'type_browse_screen.dart';

/// "TV Shows" bottom-nav destination - a thin wrapper around
/// [TypeBrowseScreen] fixed to [MediaType.tv].
class TVShowsScreen extends StatelessWidget {
  const TVShowsScreen({
    super.key,
    required this.onSelect,
    this.initialGenreId,
    this.initialLanguageCode,
    this.initialYear,
  });

  final void Function(MediaItem) onSelect;
  final int? initialGenreId;
  final String? initialLanguageCode;
  final int? initialYear;

  @override
  Widget build(BuildContext context) {
    return TypeBrowseScreen(
      mediaType: MediaType.tv,
      title: 'TV Shows',
      onSelect: onSelect,
      initialGenreId: initialGenreId,
      initialLanguageCode: initialLanguageCode,
      initialYear: initialYear,
    );
  }
}
