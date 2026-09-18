import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/media_item.dart';
import '../models/platform_filter.dart';
import '../services/tmdb_service.dart';
import '../state/settings_provider.dart';
import '../widgets/fade_in_on_scroll.dart';
import '../widgets/platform_logo.dart';
import 'platform_results_screen.dart';

const kWatchRegions = [
  ('IN', 'India'),
  ('US', 'United States'),
  ('GB', 'United Kingdom'),
  ('CA', 'Canada'),
  ('AU', 'Australia'),
];

/// Browse-by-platform home: a watch-region selector up top, then two tabs -
/// OTT services and production houses/studios - each a full grid of logo
/// cards, the same Movies/TV Shows tab split the watchlist uses. Each card
/// pushes a paginated [PlatformResultsScreen] for that provider/company.
///
/// This used to be one scrolling page with a horizontal rail per section,
/// which meant only ~4 of the 30 platforms were ever visible at once; a
/// grid per tab shows the whole catalog at a glance instead.
class PlatformsScreen extends StatefulWidget {
  const PlatformsScreen({super.key, required this.onSelect});

  final void Function(MediaItem) onSelect;

  @override
  State<PlatformsScreen> createState() => _PlatformsScreenState();
}

class _PlatformsScreenState extends State<PlatformsScreen> {
  final _tmdb = TmdbService();

  // TMDB logo_path per id, fetched once and handed down to every card that
  // doesn't already have a commonsLogo (one /watch/providers/movie call
  // covers every OTT platform; production houses need one /company/{id}
  // call each).
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

  void _openFilter(PlatformFilter filter, PlatformFilterType type, String region) {
    final logos = type == PlatformFilterType.provider ? _providerLogos : _companyLogos;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlatformResultsScreen(
          filter: filter,
          filterType: type,
          watchRegion: region,
          tmdb: _tmdb,
          onSelect: widget.onSelect,
          tmdbLogoPath: logos[filter.id],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final region = settings.watchRegion;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Platforms'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: region,
                    dropdownColor: AppTheme.surfaceVariant,
                    icon: const Icon(Icons.expand_more, color: AppTheme.textSecondary),
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    items: [
                      for (final (code, label) in kWatchRegions)
                        DropdownMenuItem(value: code, child: Text('$label ($code)')),
                    ],
                    // Persisted in settings now (it used to be local state
                    // that reset on every launch), so it also stays in sync
                    // with the same control in Settings > Playback.
                    onChanged: (value) {
                      if (value != null) settings.setWatchRegion(value);
                    },
                  ),
                ),
              ),
            ),
          ],
          bottom: TabBar(
            indicatorColor: AppTheme.resolvedAccent(context),
            indicatorWeight: 3,
            labelColor: AppTheme.resolvedAccent(context),
            unselectedLabelColor: AppTheme.textSecondary,
            tabs: [
              Tab(text: 'OTT (${kOttPlatforms.length})', icon: const Icon(Icons.live_tv_outlined, size: 20)),
              Tab(
                text: 'Production Houses (${kProductionHouses.length})',
                icon: const Icon(Icons.theaters_outlined, size: 20),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _PlatformGrid(
              filters: kOttPlatforms,
              logos: _providerLogos,
              onTap: (f) => _openFilter(f, PlatformFilterType.provider, region),
            ),
            _PlatformGrid(
              filters: kProductionHouses,
              logos: _companyLogos,
              onTap: (f) => _openFilter(f, PlatformFilterType.company, region),
            ),
          ],
        ),
      ),
    );
  }
}

/// One tab's worth of platforms as a responsive grid. Sized by max cell
/// width rather than a fixed column count so it fills sensibly on a phone,
/// a tablet and a TV without three separate breakpoints.
class _PlatformGrid extends StatelessWidget {
  const _PlatformGrid({required this.filters, required this.logos, required this.onTap});

  final List<PlatformFilter> filters;
  final Map<int, String> logos;
  final void Function(PlatformFilter) onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        mainAxisSpacing: 18,
        crossAxisSpacing: 12,
        // Square logo card plus two lines of name underneath.
        childAspectRatio: 0.72,
      ),
      itemCount: filters.length,
      itemBuilder: (context, index) {
        final filter = filters[index];
        return FadeInOnScroll(
          // A small per-card stagger so a row arrives as a ripple rather
          // than all at once, capped so later rows never feel laggy.
          delay: Duration(milliseconds: 35 * (index % 8)),
          child: _PlatformCard(
            filter: filter,
            tmdbLogoPath: logos[filter.id],
            onTap: () => onTap(filter),
          ),
        );
      },
    );
  }
}

/// A tappable card for one platform/studio - a real logo (Wikimedia
/// Commons svg or TMDB png, see [PlatformLogo]) on a white card with the
/// name below.
class _PlatformCard extends StatelessWidget {
  const _PlatformCard({required this.filter, required this.tmdbLogoPath, required this.onTap});

  final PlatformFilter filter;
  final String? tmdbLogoPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The logo is a square the full width of the grid cell; whatever
        // vertical space is left over goes to the name.
        final logoSize = constraints.maxWidth;
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlatformLogo(filter: filter, tmdbLogoPath: tmdbLogoPath, size: logoSize),
              const SizedBox(height: 8),
              Flexible(
                child: Text(
                  filter.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
