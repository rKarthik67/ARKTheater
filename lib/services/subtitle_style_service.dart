import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-customizable subtitle appearance - text color, background color,
/// and font size. Applied on both players: `BetterPlayerSubtitlesConfiguration`
/// on mobile (ExoPlayer/AVPlayer) and `SubtitleViewConfiguration`'s `style`
/// (a plain TextStyle) on desktop (mpv). Stored as raw ARGB ints/a double so
/// this has no dependency on either player package.
class SubtitleStyle {
  const SubtitleStyle({
    required this.fontColor,
    required this.backgroundColor,
    required this.fontSize,
  });

  final Color fontColor;
  final Color backgroundColor;
  final double fontSize;

  static const defaultStyle = SubtitleStyle(
    fontColor: Colors.white,
    backgroundColor: Colors.transparent,
    fontSize: 20,
  );

  SubtitleStyle copyWith({Color? fontColor, Color? backgroundColor, double? fontSize}) {
    return SubtitleStyle(
      fontColor: fontColor ?? this.fontColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      fontSize: fontSize ?? this.fontSize,
    );
  }

  // Value equality so callers can cheaply check "did this actually change"
  // before doing anything expensive (on mobile, applying a new style means
  // reloading the whole video - see MobilePlayerScreen._maybeReloadForStyle).
  @override
  bool operator ==(Object other) =>
      other is SubtitleStyle &&
      other.fontColor.value == fontColor.value &&
      other.backgroundColor.value == backgroundColor.value &&
      other.fontSize == fontSize;

  @override
  int get hashCode => Object.hash(fontColor.value, backgroundColor.value, fontSize);
}

class SubtitleStyleService {
  static const _fontColorKey = 'ark_theater.subtitle_style.font_color.v1';
  static const _backgroundColorKey = 'ark_theater.subtitle_style.background_color.v1';
  static const _fontSizeKey = 'ark_theater.subtitle_style.font_size.v1';

  Future<SubtitleStyle> load() async {
    final prefs = await SharedPreferences.getInstance();
    final fontColorValue = prefs.getInt(_fontColorKey);
    final backgroundColorValue = prefs.getInt(_backgroundColorKey);
    final fontSizeValue = prefs.getDouble(_fontSizeKey);
    return SubtitleStyle(
      fontColor: fontColorValue != null ? Color(fontColorValue) : SubtitleStyle.defaultStyle.fontColor,
      backgroundColor:
          backgroundColorValue != null ? Color(backgroundColorValue) : SubtitleStyle.defaultStyle.backgroundColor,
      fontSize: fontSizeValue ?? SubtitleStyle.defaultStyle.fontSize,
    );
  }

  Future<void> save(SubtitleStyle style) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_fontColorKey, style.fontColor.value);
    await prefs.setInt(_backgroundColorKey, style.backgroundColor.value);
    await prefs.setDouble(_fontSizeKey, style.fontSize);
  }
}
