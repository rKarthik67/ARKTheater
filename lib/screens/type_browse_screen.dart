import 'package:flutter/material.dart';
import '../core/languages.dart';
import '../core/theme.dart';
import '../models/genre.dart';
import '../models/media_item.dart';
import '../services/tmdb_service.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/paged_media_grid.dart';

/// Shared implementation behind the Movies and TV Shows bottom-nav
/// destinations: genre + language + year filters (all combinable, all
/// optional) over a paginated grid backed by TmdbService.discover(). Home's
/// per-language "View more" links open this screen with that language
/// preselected instead of duplicating the filter UI there.
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
  int? _genreId;
  String? _language;
  int? _year;

  @override
  void initState() {
    super.initState();
    _genreId = widget.initialGenreId;
    _language = widget.initialLanguageCode;
    _year = widget.initialYear;
    _genresFuture = _tmdb.genres(widget.mediaType);
  }

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  value: _year,
                  hint: const Text('Year', style: TextStyle(color: AppTheme.textSecondary)),
                  dropdownColor: AppTheme.surfaceVariant,
                  icon: const Icon(Icons.expand_more, color: AppTheme.textSecondary),
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All Years')),
                    for (var y = currentYear; y >= 1950; y--)
                      DropdownMenuItem(value: y, child: Text('$y')),
                  ],
                  onChanged: (value) => setState(() => _year = value),
                ),
              ),
            ),
          ),
        ],
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
                    _Chip(
                      label: 'All Genres',
                      selected: _genreId == null,
                      onTap: () => setState(() => _genreId = null),
                    ),
                    for (final g in genres) ...[
                      const SizedBox(width: 8),
                      _Chip(
                        label: g.name,
                        selected: g.id == _genreId,
                        onTap: () => setState(() => _genreId = g.id),
                      ),
                    ],
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
                    for (final (code, label) in kLanguages) ...[
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
                  key: ValueKey('${widget.mediaType}-$_genreId-$_language-$_year'),
                  fetchPage: (page) => _tmdb.discover(
                    widget.mediaType,
                    genreId: _genreId,
                    languageCode: _language,
                    year: _year,
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
