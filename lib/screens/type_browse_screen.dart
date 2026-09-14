import 'package:flutter/material.dart';
import '../core/languages.dart';
import '../core/theme.dart';
import '../models/genre.dart';
import '../models/media_item.dart';
import '../services/tmdb_service.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/multi_select_filter_sheet.dart';
import '../widgets/paged_media_grid.dart';

/// Shared implementation behind the Movies and TV Shows bottom-nav
/// destinations: genre + language + year filters (all combinable, all
/// optional) over a paginated grid backed by TmdbService.discover(). Home's
/// per-language "View more" links open this screen with that language
/// preselected instead of duplicating the filter UI there.
///
/// Genre and year both support selecting more than one at a time (via the
/// Filters bottom sheet) - matching the reference ARKPlay web app's
/// Movies.js/TVShows.js checkbox filters, except years here actually
/// combine correctly (see TmdbService.discover's doc comment for why the
/// reference app's own multi-year filter doesn't).
class TypeBrowseScreen extends StatefulWidget {
  const TypeBrowseScreen({
    super.key,
    required this.mediaType,
    required this.title,
    required this.onSelect,
    this.initialGenreId,
    this.initialLanguageCode,
    this.initialYear,
  });

  final MediaType mediaType;
  final String title;
  final void Function(MediaItem) onSelect;
  final int? initialGenreId;
  final String? initialLanguageCode;
  final int? initialYear;

  @override
  State<TypeBrowseScreen> createState() => _TypeBrowseScreenState();
}

class _TypeBrowseScreenState extends State<TypeBrowseScreen> {
  final _tmdb = TmdbService();
  late Future<List<Genre>> _genresFuture;
  List<int> _genreIds = [];
  String? _language;
  List<int> _years = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialGenreId != null) _genreIds = [widget.initialGenreId!];
    _language = widget.initialLanguageCode;
    if (widget.initialYear != null) _years = [widget.initialYear!];
    _genresFuture = _tmdb.genres(widget.mediaType);
  }

  void _openFilters(List<Genre> genres) {
    showMultiSelectFilterSheet(
      context: context,
      genres: genres,
      selectedGenreIds: _genreIds,
      selectedYears: _years,
      onGenresChanged: (v) => setState(() => _genreIds = v),
      onYearsChanged: (v) => setState(() => _years = v),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: FutureBuilder<List<Genre>>(
        future: _genresFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const LoadingIndicator();
          final genres = snapshot.data!;
          return Column(
            children: [
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  children: [
                    FilterSheetButton(
                      activeCount: _genreIds.length + _years.length,
                      onTap: () => _openFilters(genres),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  children: [
                    _Chip(
                      label: 'All Languages',
                      selected: _language == null,
                      onTap: () => setState(() => _language = null),
                    ),
                    for (final (code, label) in kBrowseLanguages) ...[
                      const SizedBox(width: 8),
                      _Chip(
                        label: label,
                        selected: code == _language,
                        onTap: () => setState(() => _language = code),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: PagedMediaGrid(
                  key: ValueKey('${widget.mediaType}-$_genreIds-$_language-$_years'),
                  fetchPage: (page) => _tmdb.discover(
                    widget.mediaType,
                    genreIds: _genreIds.isEmpty ? null : _genreIds,
                    languageCode: _language,
                    years: _years.isEmpty ? null : _years,
                    page: page,
                  ),
                  onSelect: widget.onSelect,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: AppTheme.accent,
      backgroundColor: AppTheme.surfaceVariant,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppTheme.textPrimary,
        fontSize: 12,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide.none,
    );
  }
}
