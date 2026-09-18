import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_fonts.dart';

/// App-wide UI settings that need to persist across launches and be
/// readable from anywhere in the widget tree: the "Liquid Glass"
/// transparency, the app accent/theme color, and per-category font family
/// + color overrides (Settings screen's "Fonts & Colors" section).
class SettingsProvider extends ChangeNotifier {
  static const _glassOpacityScaleKey = 'settings_glass_opacity_scale';
  static const _accentColorKey = 'settings_accent_color';
  static const _fontFamilyKeyPrefix = 'settings_font_family_';
  static const _fontColorKeyPrefix = 'settings_font_color_';
  static const _reduceMotionKey = 'settings_reduce_motion';
  static const _textScaleKey = 'settings_text_scale';
  static const _watchRegionKey = 'settings_watch_region';
  static const _scrollAnimationColorKey = 'settings_scroll_animation_color';

  /// Multiplies every [LiquidGlass] surface's base opacity/tint. 1.0 is the
  /// app's original, heavier frosted look; lower values push toward a very
  /// transparent, subtle "hairline glass" style (closer to shuttletv.su's
  /// nav bar); higher values push toward a heavier, more opaque frosted
  /// panel. Defaults to 0.55 (noticeably more see-through out of the box)
  /// and is always clamped to [minGlassOpacityScale, maxGlassOpacityScale].
  double _glassOpacityScale = 0.55;
  double get glassOpacityScale => _glassOpacityScale;

  // 0.0 reaches true, fully transparent glass (no tint at all - only the
  // blur/saturation and hairline border remain). The default base
  // opacity is now small (LiquidGlass's Apple-style recipe uses ~0.07),
  // so the max here is raised well past 1.0 to still give room to push
  // toward a heavier frosted look if wanted.
  static const double minGlassOpacityScale = 0.0;
  static const double maxGlassOpacityScale = 4.0;

  /// `null` means "use the app's default metallic-gold accent"
  /// (AppTheme.accent) - see AppTheme.themeFor().
  Color? _accentColor;
  Color? get accentColor => _accentColor;

  /// `null` per category means "use that category's app-default style" -
  /// see AppTheme.resolvedStyle().
  final Map<TextCategory, String?> _categoryFontId = {
    for (final c in TextCategory.values) c: null,
  };
  final Map<TextCategory, Color?> _categoryFontColor = {
    for (final c in TextCategory.values) c: null,
  };

  AppFontChoice? fontChoiceFor(TextCategory category) => findFontChoice(_categoryFontId[category]);
  Color? fontColorFor(TextCategory category) => _categoryFontColor[category];

  /// Turns off the app's scroll-in text animations (see
  /// widgets/fade_in_on_scroll.dart). Respected app-wide, and also the
  /// accessibility-friendly escape hatch for anyone who finds motion
  /// distracting or is on a slower device.
  bool _reduceMotion = false;
  bool get reduceMotion => _reduceMotion;

  /// Multiplies every text size in the app, applied once at the root via
  /// MediaQuery's textScaler (see ArkTheaterApp). 1.0 is the design size.
  double _textScale = 1.0;
  double get textScale => _textScale;

  static const double minTextScale = 0.85;
  static const double maxTextScale = 1.4;

  /// Which country's streaming catalog the Platforms screen filters by.
  /// Lived only in PlatformsScreen's local state before, so it reset on
  /// every app launch; persisting it here makes the choice stick.
  String _watchRegion = 'IN';
  String get watchRegion => _watchRegion;

  /// `null` means the scroll-in animation fades text in without any color
  /// shift. Set a color and text sweeps from that color into its own as it
  /// animates in.
  Color? _scrollAnimationColor;
  Color? get scrollAnimationColor => _scrollAnimationColor;

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  SettingsProvider() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getDouble(_glassOpacityScaleKey);
      if (stored != null) {
        _glassOpacityScale = stored.clamp(minGlassOpacityScale, maxGlassOpacityScale);
      }
      final accentValue = prefs.getInt(_accentColorKey);
      if (accentValue != null) {
        _accentColor = Color(accentValue);
      }
      _reduceMotion = prefs.getBool(_reduceMotionKey) ?? false;
      final scale = prefs.getDouble(_textScaleKey);
      if (scale != null) _textScale = scale.clamp(minTextScale, maxTextScale);
      _watchRegion = prefs.getString(_watchRegionKey) ?? 'IN';
      final scrollColor = prefs.getInt(_scrollAnimationColorKey);
      if (scrollColor != null) _scrollAnimationColor = Color(scrollColor);
      for (final category in TextCategory.values) {
        final fontId = prefs.getString('$_fontFamilyKeyPrefix${category.name}');
        if (fontId != null) _categoryFontId[category] = fontId;
        final colorValue = prefs.getInt('$_fontColorKeyPrefix${category.name}');
        if (colorValue != null) _categoryFontColor[category] = Color(colorValue);
      }
    } catch (_) {
      // Fall back to defaults if prefs are unavailable.
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }

  Future<void> setGlassOpacityScale(double value) async {
    final clamped = value.clamp(minGlassOpacityScale, maxGlassOpacityScale);
    if (clamped == _glassOpacityScale) return;
    _glassOpacityScale = clamped;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_glassOpacityScaleKey, clamped);
    } catch (_) {
      // Best-effort persistence - the in-memory value still applies this
      // session even if writing to disk fails.
    }
  }

  /// Pass `null` to reset to the app's default accent color.
  Future<void> setAccentColor(Color? color) async {
    _accentColor = color;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (color == null) {
        await prefs.remove(_accentColorKey);
      } else {
        await prefs.setInt(_accentColorKey, color.value);
      }
    } catch (_) {
      // Best-effort persistence.
    }
  }

  /// Pass `null` fontId to reset that category back to the app default font.
  Future<void> setFontForCategory(TextCategory category, String? fontId) async {
    _categoryFontId[category] = fontId;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_fontFamilyKeyPrefix${category.name}';
      if (fontId == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, fontId);
      }
    } catch (_) {
      // Best-effort persistence.
    }
  }

  /// Pass `null` color to reset that category back to its app default color.
  Future<void> setColorForCategory(TextCategory category, Color? color) async {
    _categoryFontColor[category] = color;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_fontColorKeyPrefix${category.name}';
      if (color == null) {
        await prefs.remove(key);
      } else {
        await prefs.setInt(key, color.value);
      }
    } catch (_) {
      // Best-effort persistence.
    }
  }

  Future<void> setReduceMotion(bool value) async {
    if (value == _reduceMotion) return;
    _reduceMotion = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_reduceMotionKey, value);
    } catch (_) {
      // Best-effort persistence.
    }
  }

  Future<void> setTextScale(double value) async {
    final clamped = value.clamp(minTextScale, maxTextScale);
    if (clamped == _textScale) return;
    _textScale = clamped;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_textScaleKey, clamped);
    } catch (_) {
      // Best-effort persistence.
    }
  }

  Future<void> setWatchRegion(String code) async {
    if (code == _watchRegion) return;
    _watchRegion = code;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_watchRegionKey, code);
    } catch (_) {
      // Best-effort persistence.
    }
  }

  /// Pass `null` for a plain fade with no color sweep.
  Future<void> setScrollAnimationColor(Color? color) async {
    _scrollAnimationColor = color;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (color == null) {
        await prefs.remove(_scrollAnimationColorKey);
      } else {
        await prefs.setInt(_scrollAnimationColorKey, color.value);
      }
    } catch (_) {
      // Best-effort persistence.
    }
  }
}
