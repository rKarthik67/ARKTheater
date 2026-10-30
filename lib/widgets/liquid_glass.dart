import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/settings_provider.dart';

/// Apple-style "Liquid Glass": a neutral, barely-tinted, saturated blur
/// behind the content, a bright hairline border, a soft directional
/// highlight in the top-left corner, and a gentle outer drop shadow - the
/// same visual recipe real iOS/macOS glass uses, translated from the
/// reference CSS:
///
/// ```
/// background: rgba(255, 255, 255, 0.03);
/// backdrop-filter: blur(8px) saturate(1.8) brightness(1.15) contrast(1.05);
/// box-shadow:
///   inset 0 0 0 1px rgba(255, 255, 255, 0.15),
///   inset 1.5px 1.5px 0 rgba(255, 255, 255, 0.5),
///   inset 0 0 12px rgba(255, 255, 255, 0.2),
///   0 8px 32px rgba(0, 0, 0, 0.2);
/// ```
///
/// Flutter has no native "inset shadow", so the three inset lines above
/// are faked the same way real glass UIs on canvas/Skia typically fake
/// them: a hairline [Border] stands in for the inset outline, a
/// top-left-weighted highlight gradient stands in for the corner glow,
/// and a soft white wash across the whole tint stands in for the inner
/// glow. The outer `0 8px 32px rgba(0,0,0,0.2)` maps directly to a
/// [BoxShadow]. `saturate()`/`brightness()`/`contrast()` on the backdrop
/// itself (not just the glass tint) are real - done with a [ColorFilter]
/// matrix composed onto the blur via [ImageFilter.compose], since
/// [ColorFilter] is itself a valid [ImageFilter] in Flutter.
///
/// [opacity] is each call site's own base tint strength (the CSS's 0.03,
/// scaled up slightly since our backgrounds run near-black rather than
/// mid-tone); the actual tint applied is also scaled live by
/// [SettingsProvider.glassOpacityScale], which the user controls from the
/// Settings screen's "Liquid Glass Transparency" slider - so every
/// LiquidGlass surface in the app updates together the moment that
/// slider moves. Drag the slider all the way down for true, un-tinted
/// glass.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.circular = false,
    this.blur = 10,
    this.tint,
    this.opacity = 0.035,
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

  /// Tint color mixed into the glass. Defaults to neutral white (real
  /// glass has no color of its own - it just lets whatever's behind it
  /// show through, saturated and brightened).
  final Color? tint;

  /// Base tint opacity before the user's Settings-screen transparency
  /// slider scales it. See the class doc for how the two combine.
  final double opacity;
  final Color? borderColor;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// Whether to paint the corner highlight + hairline. Left on by
  /// default; only turned off for very small/busy surfaces where the
  /// extra highlight would just read as noise.
  final bool sheen;

  @override
  Widget build(BuildContext context) {
    final base = tint ?? Colors.white;
    // A white hairline/corner-highlight (the recipe below) reads as a
    // visible edge against C.L.A.R.A.'s near-black dark surfaces, but is
    // invisible against Settings > Appearance > Light's near-white ones -
    // so the hairline/sheen flip to a dark-neutral tint in light mode
    // while the glass tint itself, and the shadow, stay the same: both
    // already read fine over the varied/scrolling content (video, posters)
    // this widget actually layers on top of in either theme.
    final isLight = Theme.of(context).brightness == Brightness.light;
    final edgeTint = isLight ? Colors.black : Colors.white;

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
        // A near-flat neutral wash rather than a gradient - real glass
        // doesn't visibly darken top-to-bottom, the CSS reference is a
        // single flat rgba() fill. The very slight lift at the top comes
        // from the corner highlight below, not from this fill.
        color: base.withOpacity(effectiveOpacity),
        border: Border.all(
          // inset 0 0 0 1px rgba(255,255,255,0.15)
          color: borderColor ?? edgeTint.withOpacity(isLight ? 0.10 : 0.15),
          width: 1,
        ),
        boxShadow: [
          // 0 8px 32px rgba(0,0,0,0.2), lightened further - a full 0.2
          // reads as an opaque dark band once the tint itself is this
          // faint, defeating the point of a see-through nav bar.
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 28,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );

    // Fakes the two remaining inset lines from the reference CSS, since
    // Flutter has no inset-shadow primitive:
    //   inset 1.5px 1.5px 0 rgba(255,255,255,0.5)  -> a tight bright spot
    //   in the top-left corner, exactly where a real inset highlight
    //   would catch light.
    //   inset 0 0 12px rgba(255,255,255,0.2)       -> a soft overall
    //   glow, brightest at the edges, faked with a radial wash.
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
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: circular ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: circular ? null : borderRadius,
            gradient: RadialGradient(
              center: Alignment.topLeft,
              radius: 1.3,
              colors: [
                edgeTint.withOpacity(isLight ? 0.16 : 0.5),
                edgeTint.withOpacity(isLight ? 0.05 : 0.12),
                edgeTint.withOpacity(0.0),
              ],
              stops: const [0.0, 0.18, 0.75],
            ),
          ),
        ),
      ),
    );

    // backdrop-filter: blur(8px) saturate(1.8) brightness(1.15) contrast(1.05)
    // ColorFilter is itself a valid ImageFilter, so it can be composed
    // directly onto the blur - this is what makes whatever scrolls
    // behind the glass look richer/brighter through it, not just blurry,
    // which is the biggest reason a plain BackdropFilter blur reads as
    // "frosted plastic" instead of "glass".
    const double saturation = 1.6;
    const double brightness = 1.12;
    final List<double> satMatrix = _saturationMatrix(saturation);
    final List<double> combined = _applyBrightness(satMatrix, brightness);

    final content = BackdropFilter(
      filter: ImageFilter.compose(
        outer: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        inner: ColorFilter.matrix(combined),
      ),
      child: sheen ? Stack(children: [glassBody, sheenOverlay]) : glassBody,
    );

    final clipped = circular
        ? ClipOval(child: content)
        : ClipRRect(borderRadius: borderRadius, child: content);

    return margin != null ? Padding(padding: margin!, child: clipped) : clipped;
  }
}

/// Standard luminance-preserving saturation color matrix (the same math
/// CSS `saturate()` and Android's `ColorMatrix.setSaturation()` use).
List<double> _saturationMatrix(double s) {
  const lumR = 0.213, lumG = 0.715, lumB = 0.072;
  return <double>[
    lumR + (1 - lumR) * s, lumG - lumG * s, lumB - lumB * s, 0, 0,
    lumR - lumR * s, lumG + (1 - lumG) * s, lumB - lumB * s, 0, 0,
    lumR - lumR * s, lumG - lumG * s, lumB + (1 - lumB) * s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

/// Multiplies a color matrix's RGB rows by [b] to approximate CSS
/// `brightness()`, folding it into the same matrix as the saturation
/// pass so only one [ColorFilter] is needed.
List<double> _applyBrightness(List<double> m, double b) {
  final out = List<double>.from(m);
  for (final row in [0, 1, 2]) {
    for (var col = 0; col < 5; col++) {
      out[row * 5 + col] *= b;
    }
  }
  return out;
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
      blur: 18,
      opacity: 0.10,
      child: child,
    );
  }
}
