import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_fonts.dart';
import '../core/theme.dart';
import '../models/media_item.dart';
import '../state/settings_provider.dart';
import 'watchlist_screen.dart';

/// Settings tab - replaces the old standalone "Watchlist" bottom-nav
/// entry. The watchlist itself moved here (first list tile below) rather
/// than disappearing, plus a slider that controls how transparent every
/// "Liquid Glass" surface in the app (nav bar, sheets, player controls)
/// renders, live.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.onSelect});

  final void Function(MediaItem) onSelect;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionLabel('Library'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: AppTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppTheme.border),
            ),
            child: ListTile(
              leading: const Icon(Icons.bookmark_outline, color: AppTheme.accent),
              title: const Text('My Watchlist'),
              subtitle: const Text(
                'Titles you bookmarked',
                style: AppTheme.metaStyle,
              ),
              trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WatchlistScreen(onSelect: onSelect),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _SectionLabel('Appearance'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: AppTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppTheme.border),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.blur_on, color: AppTheme.accent, size: 20),
                      const SizedBox(width: 10),
                      const Text('Liquid Glass Transparency', style: AppTheme.cardTitleStyle),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Controls how see-through the nav bar, sheets, and '
                    'player controls are. Left = clearer glass, right = '
                    'more frosted.',
                    style: AppTheme.metaStyle,
                  ),
                  Row(
                    children: [
                      const Icon(Icons.opacity, size: 16, color: AppTheme.textSecondary),
                      Expanded(
                        child: Slider(
                          value: settings.glassOpacityScale,
                          min: SettingsProvider.minGlassOpacityScale,
                          max: SettingsProvider.maxGlassOpacityScale,
                          divisions: 26,
                          label: settings.glassOpacityScale.toStringAsFixed(2),
                          onChanged: settings.isLoaded
                              ? (value) => settings.setGlassOpacityScale(value)
                              : null,
                        ),
                      ),
                      const Icon(Icons.gradient, size: 18, color: AppTheme.textSecondary),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SectionLabel('App Theme'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: AppTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppTheme.border),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.palette_outlined, color: AppTheme.accent, size: 20),
                      const SizedBox(width: 10),
                      const Text('Accent Color', style: AppTheme.cardTitleStyle),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Recolors buttons, the slider, selected nav items, and '
                    'the app bar. A few individually-painted highlights '
                    'elsewhere keep the default gold for now.',
                    style: AppTheme.metaStyle,
                  ),
                  const SizedBox(height: 12),
                  _ColorSwatchRow(
                    selected: settings.accentColor,
                    defaultColor: AppTheme.accent,
                    onSelect: (color) => settings.setAccentColor(color),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SectionLabel('Fonts & Colors'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: AppTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppTheme.border),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.text_fields, color: AppTheme.accent, size: 20),
                      const SizedBox(width: 10),
                      const Text('Text Font & Color', style: AppTheme.cardTitleStyle),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Pick a font family and color independently for each '
                    'kind of text in the app.',
                    style: AppTheme.metaStyle,
                  ),
                  const SizedBox(height: 8),
                  for (final category in TextCategory.values)
                    _FontCategoryTile(category: category, settings: settings),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// One row of selectable color swatches (plus a "reset to default" tile) -
/// shared by the accent-color picker and each font-color picker below.
class _ColorSwatchRow extends StatelessWidget {
  const _ColorSwatchRow({required this.selected, required this.defaultColor, required this.onSelect});

  /// `null` means "using the default" - shown with the reset tile highlighted.
  final Color? selected;
  final Color defaultColor;
  final void Function(Color?) onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _SwatchDot(
          color: defaultColor,
          isSelected: selected == null,
          isDefaultTile: true,
          onTap: () => onSelect(null),
        ),
        for (final color in kAppColorSwatches)
          _SwatchDot(
            color: color,
            isSelected: selected == color,
            onTap: () => onSelect(color),
          ),
      ],
    );
  }
}

class _SwatchDot extends StatelessWidget {
  const _SwatchDot({
    required this.color,
    required this.isSelected,
    required this.onTap,
    this.isDefaultTile = false,
  });

  final Color color;
  final bool isSelected;
  final bool isDefaultTile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: isSelected ? Colors.white : AppTheme.border,
            width: isSelected ? 2.5 : 1,
          ),
        ),
        child: isDefaultTile
            ? const Icon(Icons.replay, size: 14, color: AppTheme.goldText)
            : (isSelected ? const Icon(Icons.check, size: 16, color: AppTheme.goldText) : null),
      ),
    );
  }
}

/// One customizable text category's row in the "Fonts & Colors" card: a
/// font-family dropdown plus a color swatch row, each independently
/// resettable back to "App Default".
class _FontCategoryTile extends StatelessWidget {
  const _FontCategoryTile({required this.category, required this.settings});

  final TextCategory category;
  final SettingsProvider settings;

  @override
  Widget build(BuildContext context) {
    final currentFont = settings.fontChoiceFor(category);
    final currentColor = settings.fontColorFor(category);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(category.label, style: AppTheme.cardTitleStyle),
          const SizedBox(height: 2),
          Text(category.description, style: AppTheme.metaStyle),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            value: currentFont?.id,
            isExpanded: true,
            dropdownColor: AppTheme.surfaceVariant,
            style: const TextStyle(fontFamily: AppTheme.sansFont, color: AppTheme.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              filled: true,
              fillColor: AppTheme.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('App Default')),
              for (final font in kAppFontChoices)
                DropdownMenuItem<String?>(
                  value: font.id,
                  child: Text(font.label, style: TextStyle(fontFamily: font.fontFamily, fontWeight: font.previewWeight)),
                ),
            ],
            onChanged: (fontId) => settings.setFontForCategory(category, fontId),
          ),
          const SizedBox(height: 10),
          _ColorSwatchRow(
            selected: currentColor,
            defaultColor: AppTheme.textPrimary,
            onSelect: (color) => settings.setColorForCategory(category, color),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Text(text.toUpperCase(), style: AppTheme.metaStyle.copyWith(letterSpacing: 1.0)),
    );
  }
}
