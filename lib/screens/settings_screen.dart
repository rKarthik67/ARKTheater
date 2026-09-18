import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
          const SizedBox(height: 24),
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
