import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/subtitle_style_service.dart';

/// Preset text colors - a small, deliberately limited palette (matching
/// the common set most player apps offer) instead of a full color wheel,
/// so this doesn't need a color-picker package dependency.
const _kTextColorPresets = <Color>[
  Colors.white,
  Colors.yellow,
  Colors.amber,
  Colors.cyanAccent,
  Colors.lightGreenAccent,
  Colors.orange,
  Colors.redAccent,
  Colors.black,
];

/// Preset backgrounds - each a complete ARGB value (color + opacity baked
/// in) so there's no separate opacity control to fiddle with.
const _kBackgroundPresets = <(String, Color)>[
  ('None', Colors.transparent),
  ('Black', Color(0xB3000000)),
  ('Solid black', Colors.black),
  ('White', Color(0xB3FFFFFF)),
  ('Yellow', Color(0x80FFEB3B)),
];

/// Bottom sheet for customizing subtitle text color, background, and font
/// size - shared by both player screens. Every tap applies immediately via
/// [onChanged] (same "no separate save button" pattern as the subtitle sync
/// +/- controls), so the live preview at the top always reflects exactly
/// what's currently in effect.
Future<void> showSubtitleStyleSheet({
  required BuildContext context,
  required SubtitleStyle current,
  required ValueChanged<SubtitleStyle> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF141414),
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        var style = current;
        void apply(SubtitleStyle next) {
          style = next;
          onChanged(next);
          setSheetState(() {});
        }
        // Continuous drag ticks only update the live preview shown in this
        // sheet - they do NOT call the outer onChanged (which persists to
        // SharedPreferences and, on the mobile player, marks the style as
        // "changed" so the sheet-close handler reloads the video). Only
        // onChangeEnd below commits the value, so dragging the slider fires
        // one persist+reload instead of dozens.
        void previewOnly(SubtitleStyle next) {
          style = next;
          setSheetState(() {});
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Subtitle appearance',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                // Live preview, styled exactly like a real subtitle line.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      color: style.backgroundColor,
                      child: Text(
                        'Sample subtitle text',
                        style: TextStyle(color: style.fontColor, fontSize: style.fontSize),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Font size', style: TextStyle(color: Colors.white70, fontSize: 13)),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: style.fontSize,
                        min: 12,
                        max: 40,
                        divisions: 28,
                        activeColor: AppTheme.accent,
                        label: style.fontSize.round().toString(),
                        onChanged: (value) => previewOnly(style.copyWith(fontSize: value)),
                        onChangeEnd: (value) => apply(style.copyWith(fontSize: value)),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text(
                        style.fontSize.round().toString(),
                        textAlign: TextAlign.end,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Text color', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final color in _kTextColorPresets)
                      _ColorSwatch(
                        color: color,
                        selected: style.fontColor.value == color.value,
                        onTap: () => apply(style.copyWith(fontColor: color)),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('Background', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final (label, color) in _kBackgroundPresets)
                      _BackgroundSwatch(
                        label: label,
                        color: color,
                        selected: style.backgroundColor.value == color.value,
                        onTap: () => apply(style.copyWith(backgroundColor: color)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => apply(SubtitleStyle.defaultStyle),
                    child: const Text('Reset to default'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppTheme.accent : Colors.white24,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check,
                size: 18,
                color: ThemeData.estimateBrightnessForColor(color) == Brightness.dark
                    ? Colors.white
                    : Colors.black,
              )
            : null,
      ),
    );
  }
}

class _BackgroundSwatch extends StatelessWidget {
  const _BackgroundSwatch({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color == Colors.transparent ? const Color(0xFF211A38) : color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? AppTheme.accent : Colors.white24, width: selected ? 2 : 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color == Colors.transparent || ThemeData.estimateBrightnessForColor(color) == Brightness.dark
                ? Colors.white
                : Colors.black,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
