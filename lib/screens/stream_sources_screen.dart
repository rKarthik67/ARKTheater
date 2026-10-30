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
          Text(
            'Choose the active stream service. The HTTPS Oracle endpoint is primary; backups and your selection are saved on this device.',
            style: AppTheme.metaStyle(context),
          ),
          const SizedBox(height: 16),
          _SourceOption(
            label: 'Primary server',
            url: AppConfig.primaryScraperBaseUrl,
            selected: active == AppConfig.primaryScraperBaseUrl,
            onTap: () =>
                settings.setScraperBaseUrl(AppConfig.primaryScraperBaseUrl),
          ),
          const SizedBox(height: 10),
          _SourceOption(
            label: 'Backup server — Oracle direct',
            url: AppConfig.oracleScraperBaseUrl,
            selected: active == AppConfig.oracleScraperBaseUrl,
            onTap: () =>
                settings.setScraperBaseUrl(AppConfig.oracleScraperBaseUrl),
          ),
          const SizedBox(height: 10),
          _SourceOption(
            label: 'Backup server — Vercel',
            url: AppConfig.vercelScraperBaseUrl,
            selected: active == AppConfig.vercelScraperBaseUrl,
            onTap: () =>
                settings.setScraperBaseUrl(AppConfig.vercelScraperBaseUrl),
          ),
          const SizedBox(height: 10),
          _SourceOption(
            label: 'Torrent source',
            url: settings.torrentSourceUrl ??
                'Configure a compatible torrent resolver',
            selected: active == settings.torrentSourceUrl,
            onTap: () => settings.torrentSourceUrl == null
                ? _configureTorrentSource(context, settings)
                : settings.setScraperBaseUrl(settings.torrentSourceUrl!),
            trailing: settings.torrentSourceUrl == null
                ? null
                : IconButton(
                    tooltip: 'Remove torrent source',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: settings.removeTorrentSourceUrl,
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              'Use only a resolver you operate or are authorized to use. It must provide ARKTheater\'s /api/v2 stream API.',
              style: AppTheme.metaStyle(context),
            ),
          ),
          if (settings.customScraperBackupUrl != null) ...[
            const SizedBox(height: 10),
            _SourceOption(
              label: 'Custom backup server',
              url: settings.customScraperBackupUrl!,
              selected: active == settings.customScraperBackupUrl,
              onTap: () =>
                  settings.setScraperBaseUrl(settings.customScraperBackupUrl!),
              trailing: IconButton(
                tooltip: 'Remove custom backup',
                icon: const Icon(Icons.delete_outline),
                onPressed: settings.removeCustomScraperBackupUrl,
              ),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _addCustomBackup(context, settings),
            icon: const Icon(Icons.add_link),
            label: Text(settings.customScraperBackupUrl == null
                ? 'Add custom backup server'
                : 'Replace custom backup server'),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: active == AppConfig.primaryScraperBaseUrl
                ? null
                : settings.resetScraperBaseUrl,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset to primary server'),
          ),
        ],
      ),
    );
  }

  Future<void> _addCustomBackup(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final controller =
        TextEditingController(text: settings.customScraperBackupUrl ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Custom backup server'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://example.com',
            helperText: 'Use a full HTTP or HTTPS API address.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    final saved = await settings.setCustomScraperBackupUrl(value);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(saved
          ? 'Custom backup server saved.'
          : 'Enter a valid full HTTP or HTTPS URL.'),
    ));
  }

  Future<void> _configureTorrentSource(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final controller =
        TextEditingController(text: settings.torrentSourceUrl ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Torrent source'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://your-resolver.example',
            helperText: 'A resolver you operate, compatible with /api/v2.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    final saved = await settings.setTorrentSourceUrl(value);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(saved
          ? 'Torrent source saved. Select it to make it active.'
          : 'Enter a valid full HTTP or HTTPS URL.'),
    ));
  }
}

class _SourceOption extends StatelessWidget {
  const _SourceOption({
    required this.label,
    required this.url,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final String url;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
        color: selected
            ? AppTheme.accent.withOpacity(0.14)
            : AppTheme.surfaceVariantOf(context),
        child: RadioListTile<bool>(
          value: true,
          groupValue: selected,
          onChanged: (_) => onTap(),
          activeColor: AppTheme.resolvedAccent(context),
          title: Text(label),
          subtitle: Text(url, style: AppTheme.metaStyle(context)),
          secondary: trailing,
        ),
      );
}
