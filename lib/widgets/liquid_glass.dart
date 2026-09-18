import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/settings_provider.dart';

/// "Liquid Glass" surface: a blurred backdrop behind a translucent tinted
/// gradient, a soft diagonal specular sweep, a bright hairline catching
/// light along the top edge, a hairline border, and a soft ambient shadow
/// (plus a faint gold glow, echoing C.L.A.R.A.'s focus-ring treatment) -
/// used for every menu-like surface in the app: the bottom nav / side
/// rail, filter and subtitle sheets, the provider switcher, and the
/// player's on-screen controls.
///
/// The base look is tuned to sit closer to shuttletv.su's top nav pill -
/// a much more see-through, lightly tinted glass (their nav measures out
/// to roughly a 0.1-opacity black tint plus a 0.5px white inset hairline,
/// with the "glass" look coming mostly from an SVG refraction filter
/// rather than a heavy blur/tint) - than the heavier frosted panel this
/// started as. True SVG-style chromatic-aberration refraction isn't
/// practical to reproduce with Flutter's built-in filters, so this stays
/// with blur + gradient + hairline, just pushed much more transparent by
/// default.
///
/// [opacity] is each call site's own base tint strength; the actual tint
/// applied is also scaled live by [SettingsProvider.glassOpacityScale],
/// which the user controls from the Settings screen's "Liquid Glass
/// Transparency" slider - so every LiquidGlass surface in the app updates
/// together the moment that slider moves.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.circular = false,
    this.blur = 18,
    this.tint,
    this.opacity = 0.34,
    this.borderColor,
    this.padding,
    this.margin,
    this.sheen = true,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// Renders as a circle (radius comes from the child's own size) instead
  /// of a rounded rectangle - for small round controls like icon buttons.
  final bool circular;
  final double blur;
  final Color? tint;

  /// Base tint opacity before the user's Settings-screen transparency
  /// slider scales it. See the class doc for how the two combine.
  final double opacity;
  final Color? borderColor;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// Whether to paint the specular highlight sweep + bright top edge.
  /// Left on by default; only turned off for very small/busy surfaces
  /// where the extra highlight would just read as noise.
  final bool sheen;

  @override
  Widget build(BuildContext context) {
    final base = tint ?? AppTheme.surface;

    // Falls back to the default scale (1.0) if SettingsProvider isn't in
    // the tree yet (e.g. a widget test that doesn't wire providers) -
    // Provider.of with listen:false + a try/catch avoids a hard crash.
    double scale = 1.0;
    try {
      scale = context.watch<SettingsProvider>().glassOpacityScale;
    } catch (_) {
      // No SettingsProvider ancestor - keep the default scale.
    }
    final effectiveOpacity = (opacity * scale).clamp(0.0, 1.0);

    final glassBody = Container(
      padding: padding,
      decoration: BoxDecoration(
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withOpacity(0.10),
            base.withOpacity(effectiveOpacity * 0.88),
            base.withOpacity(effectiveOpacity),
          ],
          stops: const [0.0, 0.42, 1.0],
        ),
        border: Border.all(
          color: borderColor ?? Colors.white.withOpacity(0.10),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: AppTheme.accentGlow,
            blurRadius: 28,
            spreadRadius: -10,
          ),
        ],
      ),
      child: child,
    );

    // The diagonal "liquid" sheen - a soft light band raking across the
    // upper-left, like light grazing a curved glass surface - plus a
    // bright rim along the very top edge where that light concentrates.
    //
    // Wrapped in Positioned.fill so it's never the ONLY kind of child in
    // whatever Stack it ends up in: a Stack made entirely of Positioned
    // children has to size itself to its incoming constraints, which
    // blows up ('size.isFinite' assertion) the moment LiquidGlass sits
    // somewhere with unbounded width - e.g. as a non-Expanded child of a
    // Row, which is exactly how the desktop/tablet NavigationRail branch
    // of ResponsiveScaffold uses it. Keeping glassBody as the outer
    // Stack's one real (non-Positioned) child means that Stack always
    // sizes itself from glassBody's own finite size instead.
    final sheenOverlay = Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: circular ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: circular ? null : borderRadius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.14),
                    Colors.white.withOpacity(0.0),
                  ],
                  stops: const [0.0, 0.55],
                ),
              ),
            ),
          ),
          if (!circular)
            Positioned(
              top: 0,
              left: borderRadius.topLeft.x,
              right: borderRadius.topRight.x,
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.0),
                      Colors.white.withOpacity(0.5),
                      Colors.white.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final content = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: sheen ? Stack(children: [glassBody, sheenOverlay]) : glassBody,
    );

    final clipped = circular
        ? ClipOval(child: content)
        : ClipRRect(borderRadius: borderRadius, child: content);

    return margin != null ? Padding(padding: margin!, child: clipped) : clipped;
  }
}

/// Wraps a modal bottom sheet's content in liquid glass with rounded top
/// corners. Pair with `backgroundColor: Colors.transparent` (already the
/// app-wide default via [AppTheme.dark]'s `bottomSheetTheme`) on
/// [showModalBottomSheet] so the frosted effect actually shows instead of
/// being painted over by the sheet's own opaque default background.
class LiquidGlassSheet extends StatelessWidget {
  const LiquidGlassSheet({super.key, required this.child, this.borderRadius});

  final Widget child;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      borderRadius: borderRadius ?? const BorderRadius.vertical(top: Radius.circular(24)),
      blur: 22,
      opacity: 0.52,
      child: child,
    );
  }
}
