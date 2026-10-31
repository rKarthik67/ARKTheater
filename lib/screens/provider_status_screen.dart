import 'package:flutter/material.dart';

import '../core/app_fonts.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../video_providers/scraper_api.dart';

/// Read-only view of the scraper's scheduled provider checks. The checks run
/// server-side, so opening this screen never fans out a load of provider
/// requests from a user's phone/tablet.
class ProviderStatusScreen extends StatefulWidget {
  const ProviderStatusScreen({super.key});

  @override
  State<ProviderStatusScreen> createState() => _ProviderStatusScreenState();
}

class _ProviderStatusScreenState extends State<ProviderStatusScreen> {
  ProviderHealthSnapshot? _snapshot;
  String? _error;
  bool _loading = true;
  bool _runningFullCheck = false;
  String? _checkingProviderId;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh({bool runFullCheck = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _runningFullCheck = runFullCheck;
    });
    try {
      final api = ScraperApi(AppConfig.scraperBaseUrl);
      final snapshot = runFullCheck
          ? await api.checkAllProviderHealth()
          : await api.getProviderHealthStatus();
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _runningFullCheck = false;
        });
      }
    }
  }

  Future<void> _checkProvider(ProviderHealthResult provider) async {
    if (_checkingProviderId != null) return;
    setState(() => _checkingProviderId = provider.id);
    try {
      final fresh = await ScraperApi(AppConfig.scraperBaseUrl)
          .checkProviderHealth(provider.id);
      if (!mounted || _snapshot == null) return;
      final current = _snapshot!;
      final providers = [
        for (final item in current.providers)
          if (item.id == fresh.id) fresh else item,
      ];
      final online = providers.where((item) => item.isOnline).length;
      final offline = providers.where((item) => item.isOffline).length;
      setState(() {
        _snapshot = ProviderHealthSnapshot(
          updatedAt: DateTime.now(),
          interval: current.interval,
          total: providers.length,
          online: online,
          offline: offline,
          providers: providers,
        );
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not check ${provider.displayName}: $error')),
      );
    } finally {
      if (mounted) setState(() => _checkingProviderId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Provider status'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _refresh(runFullCheck: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading && snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _refresh(runFullCheck: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (_error != null)
                    _MessageCard(
                      icon: Icons.cloud_off_outlined,
                      message: 'Could not load provider status. Pull down to retry.',
                    )
                  else if (snapshot == null)
                    const _MessageCard(
                      icon: Icons.hourglass_empty,
                      message: 'No provider status is available yet.',
                    )
                  else ...[
                    _OverviewCard(
                      snapshot: snapshot,
                      runningFullCheck: _runningFullCheck,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Providers',
                      style: AppTheme.resolvedStyle(
                        context,
                        AppTheme.sectionHeaderStyle(context),
                        TextCategory.header,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final provider in snapshot.providers)
                      _ProviderTile(
                        provider: provider,
                        checking: _checkingProviderId == provider.id,
                        onTap: () => _checkProvider(provider),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.snapshot,
    required this.runningFullCheck,
  });

  final ProviderHealthSnapshot snapshot;
  final bool runningFullCheck;

  @override
  Widget build(BuildContext context) {
    final updated = snapshot.updatedAt?.toLocal();
    final interval = snapshot.interval.inMinutes;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariantOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${snapshot.online} of ${snapshot.total} providers online',
            style: AppTheme.cardTitleStyle(context).copyWith(fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            '${snapshot.offline} offline${interval > 0 ? ' · checked every $interval min' : ''}',
            style: AppTheme.metaStyle(context),
          ),
          const SizedBox(height: 4),
          Text(
            runningFullCheck
                ? 'Running a fresh check of all providers…'
                : 'Tap a provider to check it now. Pull down to check all.',
            style: AppTheme.metaStyle(context),
          ),
          if (updated != null) ...[
            const SizedBox(height: 4),
            Text('Last checked: ${MaterialLocalizations.of(context).formatMediumDate(updated)} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(updated))}', style: AppTheme.metaStyle(context)),
          ],
        ],
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.provider,
    required this.checking,
    required this.onTap,
  });

  final ProviderHealthResult provider;
  final bool checking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = provider.isOnline
        ? AppTheme.success
        : provider.isOffline
            ? AppTheme.error
            : AppTheme.warning;
    final label = provider.isOnline
        ? 'Online'
        : provider.isOffline
            ? 'Offline'
            : 'Untested';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppTheme.surfaceOf(context),
      child: ListTile(
        leading: Icon(
          provider.isOnline ? Icons.check_circle_outline : Icons.error_outline,
          color: color,
        ),
        title: Text(provider.displayName, style: AppTheme.cardTitleStyle(context)),
        subtitle: Text(
          provider.requestTime > Duration.zero
              ? '${provider.requestTime.inMilliseconds} ms'
              : 'No completed check yet',
          style: AppTheme.metaStyle(context),
        ),
        trailing: checking
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        onTap: checking ? null : onTap,
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariantOf(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textSecondaryOf(context)),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: AppTheme.metaStyle(context))),
        ],
      ),
    );
  }
}
