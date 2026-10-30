import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../core/responsive.dart';
import '../core/app_fonts.dart';
import '../core/theme.dart';
import '../models/media_item.dart';
import '../services/playback_position_service.dart';
import '../services/torrent_stream_service.dart';
import '../services/github_update_service.dart';
import '../services/watchlist_backup_service.dart';
import '../state/recently_watched_provider.dart';
import '../state/settings_provider.dart';
import '../state/watchlist_provider.dart';
import '../widgets/fade_in_on_scroll.dart';
import 'platforms_screen.dart' show kWatchRegions;
import 'provider_status_screen.dart';
import 'stream_sources_screen.dart';
import 'watchlist_screen.dart';

/// Settings tab - replaces the old standalone "Watchlist" bottom-nav
/// entry. The watchlist itself moved here (first list tile below) rather
/// than disappearing, alongside every app-wide preference: glass
/// transparency, accent color, per-category fonts and colors, text size,
/// scroll animations, the default watch region, and data housekeeping.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.onSelect});

  final void Function(MediaItem) onSelect;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _settingsTitleTaps = 0;
  bool _showStreamSources = false;
  String _installedVersion = '…';

  @override
  void initState() {
    super.initState();
    _loadInstalledVersion();
  }

  Future<void> _loadInstalledVersion() async {
    final package = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _installedVersion = package.version);
  }

  void _handleSettingsTitleTap() {
    if (_showStreamSources) return;
    _settingsTitleTaps++;
    if (_settingsTitleTaps < 3) return;
    setState(() => _showStreamSources = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stream source controls unlocked')),
    );
  }

  Future<void> _checkForUpdate() async {
    final messenger = ScaffoldMessenger.of(context);
    final updates = GitHubUpdateService();
    try {
      final update = await updates.checkForUpdate();
      if (!mounted) return;
      if (update == null) {
        messenger.showSnackBar(const SnackBar(content: Text('ARK Theater is up to date.')));
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppTheme.surfaceOf(context),
          title: Text('Version ${update.version} is ready'),
          content: Text(
            update.notes.trim().isEmpty
                ? 'Download the signed APK from GitHub and open Android\'s installer?'
                : update.notes,
            style: AppTheme.metaStyle(context),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () async {
                final allowed = await updates.canInstallPackages();
                if (!allowed) {
                  await updates.requestInstallPermission();
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Allow installs from ARK Theater, then tap Check for updates again.')),
                  );
                  return;
                }
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                messenger.showSnackBar(const SnackBar(content: Text('Downloading update…')));
                try {
                  await updates.downloadAndInstall(update);
                } catch (_) {
                  if (mounted) {
                    messenger.showSnackBar(const SnackBar(content: Text('Update download failed. Please try again.')));
                  }
                }
              },
              child: const Text('Download update'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('Could not check GitHub for updates.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final watchlist = context.watch<WatchlistProvider>();

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleSettingsTitleTap,
          child: const Text('Settings'),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(0, 8, 0, 24 + Responsive.bottomNavInset(context)),
        children: [
          // ---------------------------------------------------------------
          const _SectionLabel('Library'),
          _SettingsCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.bookmark_outline, color: AppTheme.accent),
                  title: const Text('My Watchlist'),
                  subtitle: Text('Titles you bookmarked', style: AppTheme.metaStyle(context)),
                  trailing: Icon(Icons.chevron_right, color: AppTheme.textSecondaryOf(context)),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => WatchlistScreen(onSelect: widget.onSelect)),
                    );
                  },
                ),
                Divider(height: 1, color: AppTheme.borderOf(context)),
                ListTile(
                  leading: Icon(Icons.ios_share, color: AppTheme.textSecondaryOf(context)),
                  title: const Text('Export Watchlist'),
                  subtitle: Text(
                    'Share a watchlist.json to another device (AirDrop, Messages, etc.)',
                    style: AppTheme.metaStyle(context),
                  ),
                  onTap: () => _exportWatchlist(context),
                ),
                Divider(height: 1, color: AppTheme.borderOf(context)),
                ListTile(
                  leading: Icon(Icons.file_download_outlined, color: AppTheme.textSecondaryOf(context)),
                  title: const Text('Import Watchlist'),
                  subtitle: Text(
                    'Merges a watchlist.json received from another device into this one',
                    style: AppTheme.metaStyle(context),
                  ),
                  onTap: () => _importWatchlist(context),
                ),
                Divider(height: 1, color: AppTheme.borderOf(context)),
                ListTile(
                  leading: Icon(
                    watchlist.isShared ? Icons.sync : Icons.devices_other_outlined,
                    color: watchlist.isShared ? AppTheme.accent : AppTheme.textSecondaryOf(context),
                  ),
                  title: const Text('Shared Watchlist'),
                  subtitle: Text(
                    watchlist.isShared
                        ? (watchlist.isSyncing
                            ? 'Syncing with your linked devices…'
                            : 'Connected — sync, add a device, or disconnect')
                        : 'Link devices with a four-digit, four-minute code',
                    style: AppTheme.metaStyle(context),
                  ),
                  trailing: Icon(Icons.chevron_right, color: AppTheme.textSecondaryOf(context)),
                  onTap: () => _showSharedWatchlistOptions(context),
                ),
              ],
            ),
          ),

          if (_showStreamSources) ...[
            const _SectionLabel('Stream Sources'),
            _SettingsCard(
              child: ListTile(
                leading: const Icon(Icons.dns_outlined, color: AppTheme.accent),
                title: const Text('Stream Sources'),
                subtitle: Text('Choose primary or backup server', style: AppTheme.metaStyle(context)),
                trailing: Icon(Icons.chevron_right, color: AppTheme.textSecondaryOf(context)),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StreamSourcesScreen()),
                ),
              ),
            ),
          ],

          // ---------------------------------------------------------------
          const _SectionLabel('Appearance'),
          _SettingsCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CardHeader(icon: Icons.contrast, title: 'Theme'),
                  const SizedBox(height: 6),
                  Text(
                    'Dark is ARKTheater\'s original look. Light switches to '
                    'a clean white theme in the style of Watchly.',
                    style: AppTheme.metaStyle(context),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined),
                        label: Text('Dark'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined),
                        label: Text('Light'),
                      ),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: settings.isLoaded
                        ? (modes) => settings.setThemeMode(modes.first)
                        : null,
                  ),
                ],
              ),
            ),
          ),
          _SettingsCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CardHeader(icon: Icons.blur_on, title: 'Liquid Glass Transparency'),
                  const SizedBox(height: 6),
                  Text(
                    'Controls how see-through the nav bar, sheets, and '
                    'player controls are. Left = clearer glass, right = '
                    'more frosted.',
                    style: AppTheme.metaStyle(context),
                  ),
                  Row(
                    children: [
                      Icon(Icons.opacity, size: 16, color: AppTheme.textSecondaryOf(context)),
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
                      Icon(Icons.gradient, size: 18, color: AppTheme.textSecondaryOf(context)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          _SettingsCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CardHeader(icon: Icons.format_size, title: 'Text Size'),
                  const SizedBox(height: 6),
                  Text(
                    'Scales every piece of text in the app. Handy on a TV '
                    'across the room, or to fit more on screen on a tablet.',
                    style: AppTheme.metaStyle(context),
                  ),
                  Row(
                    children: [
                      Text('A', style: TextStyle(color: AppTheme.textSecondaryOf(context), fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: settings.textScale,
                          min: SettingsProvider.minTextScale,
                          max: SettingsProvider.maxTextScale,
                          divisions: 11,
                          label: '${(settings.textScale * 100).round()}%',
                          onChanged: settings.isLoaded ? (value) => settings.setTextScale(value) : null,
                        ),
                      ),
                      Text('A', style: TextStyle(color: AppTheme.textSecondaryOf(context), fontSize: 21)),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ---------------------------------------------------------------
          const _SectionLabel('App Theme'),
          _SettingsCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CardHeader(icon: Icons.palette_outlined, title: 'Accent Color'),
                  const SizedBox(height: 6),
                  Text(
                    'Recolors buttons, the slider, selected nav items, and '
                    'the app bar. A few individually-painted highlights '
                    'elsewhere keep the default gold for now.',
                    style: AppTheme.metaStyle(context),
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

          _SettingsCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CardHeader(icon: Icons.play_circle_outline, title: 'Player Controls Color'),
                  const SizedBox(height: 6),
                  Text(
                    'Colors the mobile player timeline, loading indicator, and menus. '
                    'The first swatch follows your app accent. Open a new video after changing it.',
                    style: AppTheme.metaStyle(context),
                  ),
                  const SizedBox(height: 12),
                  _ColorSwatchRow(
                    selected: settings.playerAccentColor,
                    defaultColor: settings.accentColor ?? AppTheme.accent,
                    onSelect: (color) => settings.setPlayerAccentColor(color),
                  ),
                ],
              ),
            ),
          ),

          // ---------------------------------------------------------------
          const _SectionLabel('Motion'),
          _SettingsCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CardHeader(icon: Icons.animation, title: 'Scroll Animations'),
                  const SizedBox(height: 6),
                  Text(
                    'Choose how posters, cards, and text enter as they '
                    'scroll into view. You can still turn all motion off.',
                    style: AppTheme.metaStyle(context),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeColor: AppTheme.resolvedAccent(context),
                    title: const Text('Reduce motion', style: AppTheme.cardTitleStyle),
                    subtitle: Text(
                      'Turns all scroll-in animations off.',
                      style: AppTheme.metaStyle(context),
                    ),
                    value: settings.reduceMotion,
                    onChanged: settings.isLoaded ? (value) => settings.setReduceMotion(value) : null,
                  ),
                  if (!settings.reduceMotion) ...[
                    const SizedBox(height: 4),
                    const Text('Entrance style', style: AppTheme.cardTitleStyle),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<EntranceAnimationStyle>(
                      value: settings.entranceAnimationStyle,
                      isExpanded: true,
                      dropdownColor: AppTheme.surfaceVariantOf(context),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        filled: true,
                        fillColor: AppTheme.surfaceVariantOf(context),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppTheme.borderOf(context)),
                        ),
                      ),
                      items: [
                        for (final style in EntranceAnimationStyle.values)
                          DropdownMenuItem(
                            value: style,
                            child: Text(style.label),
                          ),
                      ],
                      onChanged: settings.isLoaded
                          ? (style) {
                              if (style != null) settings.setEntranceAnimationStyle(style);
                            }
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Text(settings.entranceAnimationStyle.description, style: AppTheme.metaStyle(context)),
                    const SizedBox(height: 14),
                    const Text('Animation sweep color', style: AppTheme.cardTitleStyle),
                    const SizedBox(height: 8),
                    _ColorSwatchRow(
                      selected: settings.scrollAnimationColor,
                      defaultColor: AppTheme.resolvedAccent(context),
                      onSelect: (color) => settings.setScrollAnimationColor(color),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ---------------------------------------------------------------
          const _SectionLabel('Fonts & Colors'),
          _SettingsCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CardHeader(icon: Icons.text_fields, title: 'Text Font & Color'),
                  const SizedBox(height: 6),
                  Text(
                    'Pick a font family and color independently for each '
                    'kind of text in the app.',
                    style: AppTheme.metaStyle(context),
                  ),
                  const SizedBox(height: 8),
                  for (final category in TextCategory.values)
                    _FontCategoryTile(category: category, settings: settings),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // ---------------------------------------------------------------
          const _SectionLabel('Catalog'),
          _SettingsCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CardHeader(icon: Icons.public, title: 'Watch Region'),
                  const SizedBox(height: 6),
                  Text(
                    'Which country\'s streaming catalog the Platforms tab '
                    'filters by. Same setting as the picker on that screen.',
                    style: AppTheme.metaStyle(context),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: settings.watchRegion,
                    isExpanded: true,
                    dropdownColor: AppTheme.surfaceVariantOf(context),
                    style: TextStyle(
                      fontFamily: AppTheme.sansFont,
                      color: AppTheme.textPrimaryOf(context),
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: AppTheme.surfaceVariantOf(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppTheme.borderOf(context)),
                      ),
                    ),
                    items: [
                      for (final (code, label) in kWatchRegions)
                        DropdownMenuItem(value: code, child: Text('$label ($code)')),
                    ],
                    onChanged: (value) {
                      if (value != null) settings.setWatchRegion(value);
                    },
                  ),
                ],
              ),
            ),
          ),

          // ---------------------------------------------------------------
          const _SectionLabel('Data & Storage'),
          _SettingsCard(
            child: Column(
              children: [
                _DangerTile(
                  icon: Icons.history_toggle_off,
                  title: 'Clear Recently Watched',
                  subtitle: 'Empties the Continue Watching row on Home.',
                  confirmMessage:
                      'Remove every title from Recently Watched? Your watchlist and saved '
                      'resume positions are untouched.',
                  onConfirmed: (context) => context.read<RecentlyWatchedProvider>().clearAll(),
                ),
                Divider(height: 1, color: AppTheme.borderOf(context)),
                _DangerTile(
                  icon: Icons.bookmark_remove_outlined,
                  title: 'Clear Watchlist',
                  subtitle: 'Removes every bookmarked title.',
                  confirmMessage: 'Remove every title from your watchlist? This can\'t be undone.',
                  onConfirmed: (context) => context.read<WatchlistProvider>().clearAll(),
                ),
                Divider(height: 1, color: AppTheme.borderOf(context)),
                _DangerTile(
                  icon: Icons.restore,
                  title: 'Clear Resume Positions',
                  subtitle: 'Every title starts from the beginning again.',
                  confirmMessage:
                      'Forget where you left off in every title? The titles themselves stay '
                      'in Recently Watched.',
                  onConfirmed: (_) => PlaybackPositionService().clearAll(),
                ),
                Divider(height: 1, color: AppTheme.borderOf(context)),
                _DangerTile(
                  icon: Icons.image_not_supported_outlined,
                  title: 'Clear Image Cache',
                  subtitle: 'Frees memory if posters look stale or wrong.',
                  confirmMessage:
                      'Drop all cached poster and backdrop images from memory? They\'ll be '
                      'fetched again as you browse.',
                  onConfirmed: (_) async {
                    PaintingBinding.instance.imageCache
                      ..clear()
                      ..clearLiveImages();
                  },
                ),
                Divider(height: 1, color: AppTheme.borderOf(context)),
                _DangerTile(
                  icon: Icons.hub_outlined,
                  title: 'Clear Torrent Cache',
                  subtitle: 'Frees disk space used by streamed and queued torrent data.',
                  confirmMessage:
                      'Delete all torrent stream and download cache files? Anything in '
                      'progress will stop.',
                  onConfirmed: (_) => TorrentStreamService.clearCache(),
                ),
              ],
            ),
          ),

          // ---------------------------------------------------------------
          const _SectionLabel('About'),
          _SettingsCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CardHeader(icon: Icons.info_outline, title: 'ARK Theater'),
                  const SizedBox(height: 8),
                  Text('Version $_installedVersion', style: AppTheme.metaStyle(context)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _checkForUpdate,
                    icon: const Icon(Icons.system_update_outlined),
                    label: const Text('Check for Android update'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ProviderStatusScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.monitor_heart_outlined),
                    label: const Text('Check provider status'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Title data, artwork, and cast information provided by '
                    'The Movie Database (TMDB). This product uses the TMDB '
                    'API but is not endorsed or certified by TMDB.',
                    style: AppTheme.metaStyle(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showSharedWatchlistOptions(BuildContext context) async {
  final watchlist = context.read<WatchlistProvider>();
  if (!watchlist.isShared) {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          const ListTile(
            title: Text('Shared Watchlist'),
            subtitle: Text('Your local titles are merged safely with linked devices.'),
            ),
            ListTile(
              leading: const Icon(Icons.add_link, color: AppTheme.accent),
              title: const Text('Create shared watchlist'),
              subtitle: const Text('Make this device the first linked device'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _createSharedWatchlist(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.link, color: AppTheme.textSecondaryOf(context)),
              title: const Text('Join with a code'),
              subtitle: const Text('Enter a four-digit code from an already linked device'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _joinSharedWatchlist(context);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text('Shared Watchlist'),
            subtitle: Text('New additions and removals sync to all linked devices.'),
          ),
          ListTile(
            leading: const Icon(Icons.sync, color: AppTheme.accent),
            title: const Text('Sync now'),
            onTap: () async {
              Navigator.pop(sheetContext);
              await _syncSharedWatchlist(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.phonelink_setup_outlined, color: AppTheme.textSecondaryOf(context)),
            title: const Text('Add another device'),
            subtitle: const Text('Creates a one-use code valid for four minutes'),
            onTap: () async {
              Navigator.pop(sheetContext);
              await _showPairingCode(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.link_off, color: AppTheme.textSecondaryOf(context)),
            title: const Text('Disconnect this device'),
            subtitle: const Text('Keeps your local titles and the shared library intact'),
            onTap: () async {
              Navigator.pop(sheetContext);
              await _disconnectSharedWatchlist(context);
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

Future<void> _createSharedWatchlist(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await context.read<WatchlistProvider>().createSharedWatchlist();
    if (!context.mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('Shared watchlist created. Add another device to generate a code.')));
  } catch (error) {
    if (context.mounted) messenger.showSnackBar(SnackBar(content: Text("Couldn't create shared watchlist: $error")));
  }
}

Future<void> _joinSharedWatchlist(BuildContext context) async {
  final controller = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Join shared watchlist'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        decoration: const InputDecoration(hintText: 'Four-digit code'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: const Text('Join'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (code == null || code.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final result = await context.read<WatchlistProvider>().joinSharedWatchlist(code);
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('Connected — ${result.added} title(s) added from the shared watchlist.')));
  } catch (error) {
    if (context.mounted) messenger.showSnackBar(SnackBar(content: Text("Couldn't join shared watchlist: $error")));
  }
}

Future<void> _syncSharedWatchlist(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final result = await context.read<WatchlistProvider>().syncNow();
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(
      result.added == 0 ? 'Watchlist is already up to date.' : 'Synced — ${result.added} title(s) added.',
    )));
  } catch (error) {
    if (context.mounted) messenger.showSnackBar(SnackBar(content: Text("Couldn't sync watchlist: $error")));
  }
}

Future<void> _showPairingCode(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final pairing = await context.read<WatchlistProvider>().createPairingCode();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add another device'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('On the other device, choose “Join with a code” and enter:'),
            const SizedBox(height: 16),
            Text(pairing.code, style: Theme.of(dialogContext).textTheme.displaySmall?.copyWith(letterSpacing: 8)),
            const SizedBox(height: 16),
            const Text('This code is one-use and expires in four minutes.', textAlign: TextAlign.center),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Done'))],
      ),
    );
  } catch (error) {
    if (context.mounted) messenger.showSnackBar(SnackBar(content: Text("Couldn't create pairing code: $error")));
  }
}

Future<void> _disconnectSharedWatchlist(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Disconnect this device?'),
      content: const Text('This device will stop syncing. Its local titles and the shared watchlist on other devices are kept.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Disconnect')),
      ],
    ),
  );
  if (confirmed != true) return;
  await context.read<WatchlistProvider>().disconnectSharedWatchlist();
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This device was disconnected from the shared watchlist.')));
}

/// "Export Watchlist" (Settings > Library) - shares the current watchlist
/// as a JSON file via the native share sheet. A quick empty-list check
/// avoids popping the whole share sheet for a file with nothing in it.
Future<void> _exportWatchlist(BuildContext context) async {
  final watchlist = context.read<WatchlistProvider>();
  final messenger = ScaffoldMessenger.of(context);
  if (watchlist.items.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text("Your watchlist is empty - nothing to export.")));
    return;
  }
  try {
    final shared = await WatchlistBackupService().exportAndShare(
      watchlist.exportJson(),
      sharePositionOrigin: _shareOrigin(context),
    );
    if (!shared) return; // user dismissed the share sheet - not an error
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text("Exported ${watchlist.items.length} title(s).")));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text("Couldn't export the watchlist: $e")));
  }
}

/// macOS and iPad's native share popover requires a non-zero anchor rect
/// (in the source view's coordinate space) or it throws a
/// PlatformException instead of opening - phones ignore this entirely.
/// This screen doesn't wire a GlobalKey to the tapped tile, so the best
/// available anchor is this screen's own render box (roughly the visible
/// content area) rather than the exact tile position; that's still a
/// valid, non-zero rect, which is all the platform actually requires.
Rect? _shareOrigin(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize || box.size.isEmpty) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// "Import Watchlist" (Settings > Library) - reads a watchlist.json file
/// the user picks and merges it into this device's watchlist. See
/// [WatchlistProvider.importAndMerge] for the merge rule (nothing existing
/// is ever removed; matching titles stay as one entry; missing ones are
/// added).
Future<void> _importWatchlist(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  String? raw;
  try {
    raw = await WatchlistBackupService().pickAndReadJson();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text("Couldn't read that file: $e")));
    return;
  }
  if (raw == null) return; // user cancelled the picker
  if (!context.mounted) return;

  final watchlist = context.read<WatchlistProvider>();
  try {
    final incoming = watchlist.parseImportJson(raw);
    final result = await watchlist.importAndMerge(incoming);
    if (!context.mounted) return;
    final suffix = result.alreadyPresent > 0
        ? ' - ${result.alreadyPresent} were already in your watchlist.'
        : '.';
    final message = result.added == 0
        ? "Nothing new - all ${result.total} title(s) in that file are already in your watchlist."
        : "Added ${result.added} new title(s)$suffix";
    messenger.showSnackBar(SnackBar(content: Text(message)));
  } on FormatException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text("Couldn't import that file: $e")));
  }
}

/// The rounded, bordered card every settings group sits in - one place to
/// change the shape/color instead of repeating it eight times above.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeInOnScroll(
      // Cards carry images/switches as well as text, so no color sweep
      // here - just the fade and lift.
      colorSweep: false,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        color: AppTheme.surfaceOf(context),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppTheme.borderOf(context)),
        ),
        child: child,
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.resolvedAccent(context), size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: AppTheme.cardTitleStyle)),
      ],
    );
  }
}

/// A destructive action row that always asks first. The confirm dialog is
/// mandatory rather than optional because every one of these wipes data
/// with no undo.
class _DangerTile extends StatelessWidget {
  const _DangerTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.confirmMessage,
    required this.onConfirmed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String confirmMessage;
  final Future<void> Function(BuildContext context) onConfirmed;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.textSecondaryOf(context)),
      title: Text(title),
      subtitle: Text(subtitle, style: AppTheme.metaStyle(context)),
      onTap: () async {
        final messenger = ScaffoldMessenger.of(context);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppTheme.surfaceOf(context),
            title: Text(title),
            content: Text(confirmMessage, style: AppTheme.metaStyle(context)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Clear', style: TextStyle(color: Color(0xFFEF6B5A))),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) return;
        await onConfirmed(context);
        messenger.showSnackBar(SnackBar(content: Text('$title - done.')));
      },
    );
  }
}

/// One row of selectable color swatches (plus a "reset to default" tile) -
/// shared by the accent-color picker, the animation sweep color, and each
/// font-color picker below.
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
            color: isSelected ? Colors.white : AppTheme.borderOf(context),
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
          Text(category.description, style: AppTheme.metaStyle(context)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            value: currentFont?.id,
            isExpanded: true,
            dropdownColor: AppTheme.surfaceVariantOf(context),
            style: TextStyle(fontFamily: AppTheme.sansFont, color: AppTheme.textPrimaryOf(context), fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              filled: true,
              fillColor: AppTheme.surfaceVariantOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppTheme.borderOf(context)),
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
            defaultColor: AppTheme.textPrimaryOf(context),
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
    return FadeInOnScroll(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        child: Text(text.toUpperCase(), style: AppTheme.metaStyle(context).copyWith(letterSpacing: 1.0)),
      ),
    );
  }
}
