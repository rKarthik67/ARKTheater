import 'package:flutter/material.dart';
import '../models/media_item.dart';
import 'type_browse_screen.dart';

/// "Movies" bottom-nav destination - a thin wrapper around
/// [TypeBrowseScreen] fixed to [MediaType.movie].
class MoviesScreen extends StatelessWidget {
  const MoviesScreen({
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
      mediaType: MediaType.movie,
      title: 'Movies',
      onSelect: onSelect,
      initialGenreId: initialGenreId,
      initialLanguageCode: initialLanguageCode,
      initialYear: initialYear,
    );
  }
}
