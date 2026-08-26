import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/platform_filter.dart';

/// Renders one OTT platform / production house's real logo - a Wikimedia
/// Commons `.svg` when [PlatformFilter.commonsLogo] has one on file
/// (rendered via flutter_svg), otherwise a TMDB `logo_path` PNG (passed in
/// as [tmdbLogoPath], fetched separately per-screen since it needs a
/// network round trip), on the same white rounded card the reference web
/// app's `Platforms.css` uses (`.platform-logo { background: #fff }`) so
/// dark or transparent logo marks stay legible. Falls back to the
/// deterministic gradient + initials card this app used before any logo
/// data was wired up, if there's no commonsLogo, no tmdbLogoPath, or the
/// image/svg fails to load.
class PlatformLogo extends StatelessWidget {
  const PlatformLogo({
    super.key,
    required this.filter,
    this.tmdbLogoPath,
    this.size = 92,
  });

  final PlatformFilter filter;
  final String? tmdbLogoPath;
  final double size;

  @override
  Widget build(BuildContext context) {
    final svgUrl = filter.commonsLogo;
    final pngUrl = tmdbLogoPath == null ? null : 'https://image.tmdb.org/t/p/original$tmdbLogoPath';

    if (svgUrl == null && pngUrl == null) {
      return _FallbackCard(filter: filter, size: size);
    }

    // A fixed-size white card that CLIPS its child, so an error fallback
    // rendered in place of the svg/png (below) fills exactly this box
    // instead of drawing a second, differently-sized card on top of it.
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: size * 0.08, vertical: size * 0.16),
        child: svgUrl != null
            ? SvgPicture.network(
                svgUrl,
                fit: BoxFit.contain,
                placeholderBuilder: (_) => const SizedBox.shrink(),
                errorBuilder: (_, __, ___) =>
                    pngUrl != null ? _NetworkLogo(url: pngUrl, filter: filter) : _FallbackContent(filter: filter),
              )
            : _NetworkLogo(url: pngUrl!, filter: filter),
      ),
    );
  }
}

class _NetworkLogo extends StatelessWidget {
  const _NetworkLogo({required this.url, required this.filter});

  final String url;
  final PlatformFilter filter;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _FallbackContent(filter: filter),
    );
  }
}

/// Bare fallback content (colored background + initials/name, no size or
/// decoration of its own) - used when an svg/png fails to load AFTER
/// [PlatformLogo] already committed to its white card, so this just fills
/// whatever space that card's padding left rather than drawing a second,
/// independently-sized card on top of it.
class _FallbackContent extends StatelessWidget {
  const _FallbackContent({required this.filter});

  final PlatformFilter filter;

  @override
  Widget build(BuildContext context) {
    final hue = (filter.id * 47) % 360;
    final color = HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.32).toColor();
    return SizedBox.expand(
      child: Container(
        color: color,
        alignment: Alignment.center,
        child: Text(
          filter.name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 11),
        ),
      ),
    );
  }
}

/// The deterministic gradient + initials card this app showed for every
/// platform before real logos were wired up - used top-level whenever a
/// platform has neither a commonsLogo nor a TMDB logo_path at all, so the
/// row never shows a blank tile.
class _FallbackCard extends StatelessWidget {
  const _FallbackCard({required this.filter, required this.size});

  final PlatformFilter filter;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hue = (filter.id * 47) % 360;
    final color = HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.32).toColor();
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        filter.name,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}
