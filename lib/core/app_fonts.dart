/// Curated, user-selectable font catalog for the "Fonts & Colors"
/// customization in Settings, plus the named text categories that can be
/// customized independently.
///
/// Every family listed here is already bundled under assets/fonts/ and
/// declared in pubspec.yaml - same reasoning as the app's original two
/// fonts (see core/theme.dart's doc comment): bundling avoids the
/// silent-fallback failure mode of runtime font-fetching packages.
///
/// The two new families (Cinzel, Manrope) were chosen as free, license-open
/// stand-ins for the "Casko Luxury Demo" / "Bright Pasqia DEMO" fonts
/// requested - Cinzel is a wide-tracked classical/luxury display serif in
/// the same spirit as a "Luxury" display font, Manrope a clean, bright
/// geometric sans in the same spirit as a "Bright" display sans. Marcellus
/// is included as a second, more understated serif alternative. Swap in
/// the real fonts later by dropping their files into assets/fonts/, adding
/// a pubspec entry, and adding one more [AppFontChoice] below - nothing
/// else about the customization system needs to change.
library;

import 'package:flutter/material.dart';

/// The independently-customizable slots requested: section/row headers,
/// general metadata/info text (year, runtime, genre chips, etc.), and
/// cast & crew names on the detail screen.
enum TextCategory { header, info, castDetails }

extension TextCategoryLabel on TextCategory {
  String get label => switch (this) {
        TextCategory.header => 'Headers',
        TextCategory.info => 'Info & Metadata Text',
        TextCategory.castDetails => 'Cast & Crew Details',
      };

  String get description => switch (this) {
        TextCategory.header => 'Section titles like "Trending Now" and "Popular".',
        TextCategory.info => 'Year, runtime, genre chips, and similar metadata.',
        TextCategory.castDetails => 'Actor names under the cast row on a title\'s page.',
      };
}

class AppFontChoice {
  const AppFontChoice(this.id, this.label, this.fontFamily, {this.previewWeight = FontWeight.w500});

  /// Stored in SharedPreferences - keep stable once shipped.
  final String id;
  final String label;
  final String fontFamily;
  final FontWeight previewWeight;
}

/// `null` selection (shown first, "App Default") is represented by leaving
/// the per-category font choice unset - handled by the caller, not an entry
/// here, so there is exactly one obvious way to mean "don't override".
const List<AppFontChoice> kAppFontChoices = [
  AppFontChoice('instrument_serif', 'Instrument Serif (App Default Serif)', 'Instrument Serif'),
  AppFontChoice('space_grotesk', 'Space Grotesk (App Default Sans)', 'Space Grotesk'),
  AppFontChoice('cinzel', 'Cinzel (Luxury Display Serif)', 'Cinzel', previewWeight: FontWeight.w700),
  AppFontChoice('marcellus', 'Marcellus (Elegant Serif)', 'Marcellus'),
  AppFontChoice('manrope', 'Manrope (Bright Modern Sans)', 'Manrope', previewWeight: FontWeight.w600),
];

AppFontChoice? findFontChoice(String? id) {
  if (id == null) return null;
  for (final f in kAppFontChoices) {
    if (f.id == id) return f;
  }
  return null;
}

/// Curated color swatches offered for both per-category font color and the
/// app accent color - all picked to stay legible against the app's dark
/// (near-black warm brown, see AppTheme.background) surfaces.
const List<Color> kAppColorSwatches = [
  Color(0xFFF5F5F7), // app default text (near-white)
  Color(0xFFE0A83A), // app default accent (metallic gold)
  Color(0xFFF6D68A), // warm champagne
  Color(0xFFE8C4A0), // soft copper
  Color(0xFFEF6B5A), // coral red
  Color(0xFFE0526B), // rose
  Color(0xFFC77DFF), // orchid
  Color(0xFF7DA0FA), // periwinkle blue
  Color(0xFF5AD1E0), // aqua
  Color(0xFF6BD08A), // mint green
  Color(0xFFB8E05A), // lime
  Color(0xFFB0B4C0), // cool gray
];
