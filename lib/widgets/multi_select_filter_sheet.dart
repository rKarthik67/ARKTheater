import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/genre.dart';
import 'liquid_glass.dart';

/// Bottom sheet shared by the Movies/TV Shows browse screen and the
/// Search screen's browse-before-search grid, letting the user pick any
/// number of genres and any number of years at once - mirrors the
/// reference ARKPlay web app's checkbox "Filters" panel in
/// Movies.js/TVShows.js, replacing the old single-select dropdown/chip
/// behavior (one genre, one year at a time).
Future<void> showMultiSelectFilterSheet({
  required BuildContext context,
  required List<Genre> genres,
  required List<int> selectedGenreIds,
  required List<int> selectedYears,
  required ValueChanged<List<int>> onGenresChanged,
  required ValueChanged<List<int>> onYearsChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => _MultiSelectFilterSheet(
      genres: genres,
      initialGenreIds: selectedGenreIds,
      initialYears: selectedYears,
      onGenresChanged: onGenresChanged,
      onYearsChanged: onYearsChanged,
    ),
  );
}

class _MultiSelectFilterSheet extends StatefulWidget {
  const _MultiSelectFilterSheet({
    required this.genres,
    required this.initialGenreIds,
    required this.initialYears,
    required this.onGenresChanged,
    required this.onYearsChanged,
  });

  final List<Genre> genres;
  final List<int> initialGenreIds;
  final List<int> initialYears;
  final ValueChanged<List<int>> onGenresChanged;
  final ValueChanged<List<int>> onYearsChanged;

  @override
  State<_MultiSelectFilterSheet> createState() => _MultiSelectFilterSheetState();
}

class _MultiSelectFilterSheetState extends State<_MultiSelectFilterSheet> {
  late List<int> _genreIds;
  late List<int> _years;

  @override
  void initState() {
    super.initState();
    _genreIds = [...widget.initialGenreIds];
    _years = [...widget.initialYears];
  }

  void _toggleGenre(int id) {
    setState(() {
      if (!_genreIds.remove(id)) _genreIds.add(id);
    });
  }

  void _toggleYear(int year) {
    setState(() {
      if (!_years.remove(year)) _years.add(year);
    });
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: AppTheme.textSecondary,
          fontSize: 13,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return LiquidGlassSheet(
          child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Filters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    TextButton(
                      onPressed: () => setState(() {
                        _genreIds = [];
                        _years = [];
                      }),
                      child: const Text('Clear all'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  children: [
                    _sectionLabel('Genres'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final g in widget.genres)
                          FilterChip(
                            label: Text(g.name),
                            selected: _genreIds.contains(g.id),
                            onSelected: (_) => _toggleGenre(g.id),
                            selectedColor: AppTheme.accent,
                            checkmarkColor: Colors.white,
                            backgroundColor: AppTheme.surfaceVariant,
                            labelStyle: TextStyle(
                              color: _genreIds.contains(g.id) ? Colors.white : AppTheme.textPrimary,
                              fontSize: 12,
                              fontWeight: _genreIds.contains(g.id) ? FontWeight.bold : FontWeight.normal,
                            ),
                            side: BorderSide.none,
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _sectionLabel('Years'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var y = currentYear; y >= 1950; y--)
                          FilterChip(
                            label: Text('$y'),
                            selected: _years.contains(y),
                            onSelected: (_) => _toggleYear(y),
                            selectedColor: AppTheme.accent,
                            checkmarkColor: Colors.white,
                            backgroundColor: AppTheme.surfaceVariant,
                            labelStyle: TextStyle(
                              color: _years.contains(y) ? Colors.white : AppTheme.textPrimary,
                              fontSize: 12,
                              fontWeight: _years.contains(y) ? FontWeight.bold : FontWeight.normal,
                            ),
                            side: BorderSide.none,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      widget.onGenresChanged(_genreIds);
                      widget.onYearsChanged(_years);
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      _genreIds.isEmpty && _years.isEmpty
                          ? 'Apply'
                          : 'Apply (${_genreIds.length + _years.length})',
                    ),
                  ),
                ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }
}

/// Small pill button that opens the filter sheet - shows how many
/// genre+year filters are currently active so it's clear at a glance,
/// same purpose as the reference web app's "Filters" toggle button.
class FilterSheetButton extends StatelessWidget {
  const FilterSheetButton({
    super.key,
    required this.activeCount,
    required this.onTap,
  });

  final int activeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = activeCount > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ActionChip(
        avatar: Icon(
          Icons.filter_list,
          size: 18,
          color: active ? Colors.white : AppTheme.textSecondary,
        ),
        label: Text(active ? 'Filters ($activeCount)' : 'Filters'),
        onPressed: onTap,
        backgroundColor: active ? AppTheme.accent : AppTheme.surfaceVariant,
        labelStyle: TextStyle(
          color: active ? Colors.white : AppTheme.textPrimary,
          fontSize: 12,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
        ),
        side: BorderSide.none,
      ),
    );
  }
}
