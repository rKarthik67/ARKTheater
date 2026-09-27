import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../state/settings_provider.dart';

/// Hidden settings page for choosing between the two maintained stream APIs.
class StreamSourcesScreen extends StatelessWidget {
  const StreamSourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final active = settings.scraperBaseUrl;

    return Scaffold(
      appBar: AppBar(title: const Text('Stream Sources')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Text(
            'Choose the active stream service. Your selection is saved on this device.',
            style: AppTheme.metaStyle,
          ),
          const SizedBox(height: 16),
          _SourceOption(
            label: 'Primary server',
            url: AppConfig.oracleScraperBaseUrl,
            selected: active == AppConfig.oracleScraperBaseUrl,
            onTap: () => settings.setScraperBaseUrl(AppConfig.oracleScraperBaseUrl),
          ),
          const SizedBox(height: 10),
          _SourceOption(
            label: 'Backup server',
            url: AppConfig.vercelScraperBaseUrl,
            selected: active == AppConfig.vercelScraperBaseUrl,
            onTap: () => settings.setScraperBaseUrl(AppConfig.vercelScraperBaseUrl),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: active == AppConfig.oracleScraperBaseUrl
                ? null
                : settings.resetScraperBaseUrl,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset to primary server'),
          ),
        ],
      ),
    );
  }
}

class _SourceOption extends StatelessWidget {
  const _SourceOption({
    required this.label,
    required this.url,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String url;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        color: selected ? AppTheme.accent.withOpacity(0.14) : AppTheme.surfaceVariant,
        child: RadioListTile<bool>(
          value: true,
          groupValue: selected,
          onChanged: (_) => onTap(),
          activeColor: AppTheme.resolvedAccent(context),
          title: Text(label),
          subtitle: Text(url, style: AppTheme.metaStyle),
        ),
      );
}
