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
/// size - shared by both player screens. Every control here only edits a
/// local draft (reflected immediately in the live preview box and in which
/// swatch shows as selected) - nothing is persisted or applied to the
/// actual player until "Apply" is pressed, which is when [onChanged] fires
/// once with the final chosen style. Swiping the sheet away or tapping
/// outside it without pressing Apply discards the draft entirely.
Future<void> showSubtitleStyleSheet({
  required BuildContext context,
  required SubtitleStyle current,
  required ValueChanged<SubtitleStyle> onChanged,
}) {
  // Declared here, OUTSIDE the StatefulBuilder's `builder` callback, so it
  // survives across setSheetState rebuilds. Previously this lived INSIDE
  // that callback (`var style = current;` as the first line of `builder:
  // (sheetContext, setSheetState) { ... }`), which re-ran on every single
  // rebuild and reset the draft straight back to `current` each time a
  // swatch or the slider called setSheetState - so the sheet always
  // *looked* like nothing was selected (or like the old value was still
  // selected) even though the new value had already been sent onward via
  // onChanged. That mismatch, not a rendering bug, was the actual cause.
  var draft = current;

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF141414),
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        void update(SubtitleStyle next) {
          draft = next;
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
                // Live preview, styled exactly like a real subtitle line -
                // always reflects the current draft, not what's actually
                // applied to the player yet.
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
                      color: draft.backgroundColor,
                      child: Text(
                        'Sample subtitle text',
                        style: TextStyle(color: draft.fontColor, fontSize: draft.fontSize),
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
                        value: draft.fontSize,
                        min: 12,
                        max: 40,
                        divisions: 28,
                        activeColor: AppTheme.accent,
                        label: draft.fontSize.round().toString(),
                        onChanged: (value) => update(draft.copyWith(fontSize: value)),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text(
                        draft.fontSize.round().toString(),
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
                        selected: draft.fontColor.value == color.value,
                        onTap: () => update(draft.copyWith(fontColor: color)),
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
                        selected: draft.backgroundColor.value == color.value,
                        onTap: () => update(draft.copyWith(backgroundColor: color)),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => update(SubtitleStyle.defaultStyle),
                      child: const Text('Reset to default'),
                    ),
                    const Spacer(),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
                      onPressed: () {
                        onChanged(draft);
                        Navigator.of(sheetContext).pop();
                      },
                      child: const Text('Apply'),
                    ),
                  ],
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
