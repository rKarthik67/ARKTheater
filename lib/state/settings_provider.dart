import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide UI settings that need to persist across launches and be
/// readable from anywhere in the widget tree. Currently just one knob:
/// the "Liquid Glass" transparency the user controls from the Settings
/// screen slider.
class SettingsProvider extends ChangeNotifier {
  static const _glassOpacityScaleKey = 'settings_glass_opacity_scale';

  /// Multiplies every [LiquidGlass] surface's base opacity/tint. 1.0 keeps
  /// the app's own default frosted look; lower values push toward a very
  /// transparent, subtle "hairline glass" style (closer to shuttletv.su's
  /// nav bar); higher values push toward a heavier, more opaque frosted
  /// panel. Always clamped to [minGlassOpacityScale, maxGlassOpacityScale].
  double _glassOpacityScale = 1.0;
  double get glassOpacityScale => _glassOpacityScale;

  static const double minGlassOpacityScale = 0.3;
  static const double maxGlassOpacityScale = 1.6;

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
    } catch (_) {
      // Fall back to the default scale if prefs are unavailable.
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
}
