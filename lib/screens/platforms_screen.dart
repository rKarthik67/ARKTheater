import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/media_item.dart';
import '../models/platform_filter.dart';
import '../services/tmdb_service.dart';
import '../widgets/platform_logo.dart';
import 'platform_results_screen.dart';

const _kRegions = [
  ('IN', 'India'),
  ('US', 'United States'),
  ('GB', 'United Kingdom'),
  ('CA', 'Canada'),
  ('AU', 'Australia'),
];

/// Browse-by-platform home - mirrors the reference ARKPlay web app's
/// `Platforms.js`: a watch-region selector up top, then a horizontal rail
/// of OTT services and another of production houses/studios, each card
/// pushing a paginated [PlatformResultsScreen] for that provider/company.
class PlatformsScreen extends StatefulWidget {
  const PlatformsScreen({super.key, required this.onSelect});

  final void Function(MediaItem) onSelect;

  @override
  State<PlatformsScreen> createState() => _PlatformsScreenState();
}

class _PlatformsScreenState extends State<PlatformsScreen> {
  final _tmdb = TmdbService();
  String _region = 'IN';

  // TMDB logo_path per id, fetched once and handed down to every card that
  // doesn't already have a commonsLogo - same split the reference web
  // app's Platforms.js uses (one /watch/providers/movie call covers every
  // OTT platform; production houses need one /company/{id} call each).
  Map<int, String> _providerLogos = {};
  Map<int, String> _companyLogos = {};

  @override
  void initState() {
    super.initState();
    _loadLogos();
  }

  Future<void> _loadLogos() async {
    try {
      final providerLogos = await _tmdb.watchProviderLogos();
      if (mounted) setState(() => _providerLogos = providerLogos);
    } catch (_) {
      // Cards fall back to the gradient+initials card - no need to block
      // or show an error for a purely cosmetic lookup.
    }

    final missingCompanyLogos = kProductionHouses.where((c) => c.commonsLogo == null);
    final results = await Future.wait([
      for (final company in missingCompanyLogos) _tmdb.companyLogoPath(company.id),
    ]);
    if (!mounted) return;
    final companyLogos = <int, String>{};
    var i = 0;
    for (final company in missingCompanyLogos) {
      final logoPath = results[i++];
      if (logoPath != null) companyLogos[company.id] = logoPath;
    }
    setState(() => _companyLogos = companyLogos);
  }

  void _openFilter(PlatformFilter filter, PlatformFilterType type) {
    final logos = type == PlatformFilterType.provider ? _providerLogos : _companyLogos;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlatformResultsScreen(
          filter: filter,
          filterType: type,
          watchRegion: _region,
          tmdb: _tmdb,
          onSelect: widget.onSelect,
          tmdbLogoPath: logos[filter.id],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Platforms'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _region,
                  dropdownColor: AppTheme.surfaceVariant,
                  icon: const Icon(Icons.expand_more, color: AppTheme.textSecondary),
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                  items: [
                    for (final (code, label) in _kRegions)
                      DropdownMenuItem(value: code, child: Text('$label ($code)')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _region = value);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          _PlatformSection(
            title: 'OTT Platforms',
            filters: kOttPlatforms,
            logos: _providerLogos,
            onTap: (f) => _openFilter(f, PlatformFilterType.provider),
          ),
          const SizedBox(height: 8),
          _PlatformSection(
            title: 'Production Houses',
            filters: kProductionHouses,
            logos: _companyLogos,
            onTap: (f) => _openFilter(f, PlatformFilterType.company),
          ),
        ],
      ),
    );
  }
}

class _PlatformSection extends StatelessWidget {
  const _PlatformSection({required this.title, required this.filters, required this.logos, required this.onTap});

  final String title;
  final List<PlatformFilter> filters;
  final Map<int, String> logos;
  final void Function(PlatformFilter) onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 148,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) => _PlatformCard(
                filter: filters[index],
                tmdbLogoPath: logos[filters[index].id],
                onTap: () => onTap(filters[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tappable card for one platform/studio - a real logo (Wikimedia
/// Commons svg or TMDB png, see [PlatformLogo]) on a white card with the
/// name below, mirroring the reference web app's `.platform-card`/
/// `.platform-logo` layout.
class _PlatformCard extends StatelessWidget {
  const _PlatformCard({required this.filter, required this.tmdbLogoPath, required this.onTap});

  final PlatformFilter filter;
  final String? tmdbLogoPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 100,
        child: Column(
          children: [
            PlatformLogo(filter: filter, tmdbLogoPath: tmdbLogoPath, size: 100),
            const SizedBox(height: 6),
            Text(
              filter.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
