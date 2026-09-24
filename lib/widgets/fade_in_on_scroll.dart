import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/settings_provider.dart';

/// Animates its child into view using the user-selected entrance style,
/// optionally sweeping its color from an accent tint into the text's own
/// color as it arrives.
///
/// Deliberately package-free: rather than pulling in a visibility-detector
/// dependency, this subscribes to the enclosing [Scrollable]'s
/// [ScrollPosition] (which is a [ChangeNotifier]) and, on each scroll tick,
/// asks its own [RenderBox] where it currently sits relative to the
/// viewport. That means it costs nothing when nothing is scrolling, and it
/// works inside any ListView/GridView/CustomScrollView without the parent
/// having to cooperate.
///
/// The color sweep is applied with a [ColorFiltered] `srcATop` blend rather
/// than by threading a [TextStyle] through every call site: srcATop
/// repaints whatever the child draws in the tint color while preserving its
/// alpha shape, so a [Text] that hard-codes its own color still animates.
/// Keep it to text-ish subtrees - pointed at an image it would flatten the
/// image into a silhouette.
///
/// Honors [SettingsProvider.reduceMotion]: when that's on, the child is
/// returned untouched with no animation, no listener, and no rebuilds.
class FadeInOnScroll extends StatefulWidget {
  const FadeInOnScroll({
    super.key,
    required this.child,
    this.offsetY = 22,
    this.duration = const Duration(milliseconds: 520),
    this.delay = Duration.zero,
    this.colorSweep = true,
  });

  final Widget child;

  /// How far below its resting place the child starts, in logical pixels.
  final double offsetY;

  final Duration duration;

  /// Lets a caller stagger a row of siblings (card 1, then 2, then 3...).
  final Duration delay;

  /// Whether to sweep the child's color from the user's chosen animation
  /// color (Settings > Motion, defaults to the app accent) into its own.
  final bool colorSweep;

  @override
  State<FadeInOnScroll> createState() => _FadeInOnScrollState();
}

class _FadeInOnScrollState extends State<FadeInOnScroll> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curve;
  ScrollPosition? _position;
  bool _played = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    // First frame: anything already on screen at build time animates in
    // right away rather than waiting for the user to scroll.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePlay());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newPosition = Scrollable.maybeOf(context)?.position;
    if (identical(newPosition, _position)) return;
    _position?.removeListener(_maybePlay);
    _position = newPosition;
    _position?.addListener(_maybePlay);
  }

  @override
  void dispose() {
    _position?.removeListener(_maybePlay);
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Plays once, the first time any part of this widget is inside (or just
  /// below the fold of) the viewport. Scrolling back up doesn't replay it -
  /// re-animating already-seen content on every pass reads as flicker.
  void _maybePlay() {
    if (_played || !mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final screenHeight = MediaQuery.sizeOf(context).height;
    // 0.94 rather than 1.0 so the animation starts a touch before the
    // widget's top edge clears the bottom of the screen - by the time the
    // user's eye reaches it, it has already arrived.
    final isVisible = top < screenHeight * 0.94 && top + box.size.height > 0;
    if (!isVisible) return;
    _played = true;
    _position?.removeListener(_maybePlay);
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    SettingsProvider? settings;
    try {
      settings = context.watch<SettingsProvider>();
    } catch (_) {
      settings = null;
    }
    if (settings?.reduceMotion ?? false) return widget.child;

    final sweepColor = widget.colorSweep
        ? (settings?.scrollAnimationColor ?? AppTheme.resolvedAccent(context))
        : null;

    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) {
        final t = _curve.value;
        Widget content = child!;
        if (sweepColor != null && t < 1.0) {
          content = ColorFiltered(
            // Fully tinted at t=0, untouched by t=1 - so text arrives in
            // the accent color and settles into its own.
            colorFilter: ColorFilter.mode(
              sweepColor.withOpacity(1.0 - t),
              BlendMode.srcATop,
            ),
            child: content,
          );
        }
        final style = settings?.entranceAnimationStyle ?? EntranceAnimationStyle.fadeLift;
        content = switch (style) {
          EntranceAnimationStyle.fadeLift => Transform.translate(
              offset: Offset(0, widget.offsetY * (1.0 - t)),
              child: content,
            ),
          EntranceAnimationStyle.fade => content,
          EntranceAnimationStyle.scale => Transform.scale(
              scale: 0.94 + (0.06 * t),
              child: content,
            ),
          EntranceAnimationStyle.slideLeft => Transform.translate(
              offset: Offset(-widget.offsetY * 1.5 * (1.0 - t), 0),
              child: content,
            ),
          EntranceAnimationStyle.slideRight => Transform.translate(
              offset: Offset(widget.offsetY * 1.5 * (1.0 - t), 0),
              child: content,
            ),
        };
        return Opacity(
          opacity: t,
          child: content,
        );
      },
    );
  }
}
