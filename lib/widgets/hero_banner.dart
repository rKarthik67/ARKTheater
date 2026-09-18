import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/media_item.dart';
import '../screens/trailer_screen.dart';
import '../services/tmdb_service.dart';

/// Auto-rotating spotlight at the top of Home - mirrors the reference
/// ARKPlay web app's HeroSlide: full-bleed backdrop, title, overview, and
/// Watch Now / Trailer actions, cycling through a handful of current
/// releases instead of just listing them in a row.
class HeroBanner extends StatefulWidget {
  const HeroBanner({
    super.key,
    required this.items,
    required this.tmdb,
    required this.onWatchNow,
  });

  final List<MediaItem> items;
  final TmdbService tmdb;
  final void Function(MediaItem) onWatchNow;

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  final _pageController = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.items.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 6), (_) {
        if (!mounted || !_pageController.hasClients) return;
        final next = (_index + 1) % widget.items.length;
        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _watchTrailer(MediaItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final key = await widget.tmdb.trailerYoutubeKey(item.type, item.id);
    if (!mounted) return;
    if (key == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No trailer available for this title.')),
      );
      return;
    }
    navigator.push(
      MaterialPageRoute(builder: (_) => TrailerScreen(title: item.title, youtubeKey: key)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final height = MediaQuery.sizeOf(context).width >= 1024 ? 420.0 : 320.0;

    return SizedBox(
      height: height,
      child: PageView.builder(
        controller: _pageController,
        itemCount: widget.items.length,
        onPageChanged: (i) => _index = i,
        itemBuilder: (context, index) {
          final item = widget.items[index];
          final backdrop = item.backdropUrl();
          return Stack(
            fit: StackFit.expand,
            children: [
              if (backdrop != null)
                CachedNetworkImage(imageUrl: backdrop, fit: BoxFit.cover)
              else
                Container(color: AppTheme.surfaceVariant),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, AppTheme.background.withOpacity(0.95)],
                    stops: const [0.35, 1.0],
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.heroTitleStyle,
                    ),
                    const SizedBox(height: 8),
                    if ((item.overview ?? '').isNotEmpty)
                      Text(
                        item.overview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.heroOverviewStyle,
                      ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => widget.onWatchNow(item),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: AppTheme.goldText,
                          ),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Watch Now'),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: () => _watchTrailer(item),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                          ),
                          icon: const Icon(Icons.smart_display_outlined),
                          label: const Text('Trailer'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
