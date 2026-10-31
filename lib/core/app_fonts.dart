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

/// Independently-customizable text roles used throughout the app.
enum TextCategory { header, cardTitle, body, info, castDetails, button, navigation }

extension TextCategoryLabel on TextCategory {
  String get label => switch (this) {
        TextCategory.header => 'Headers',
        TextCategory.cardTitle => 'Poster & Card Titles',
        TextCategory.body => 'Descriptions & Body Text',
        TextCategory.info => 'Info & Metadata Text',
        TextCategory.castDetails => 'Cast & Crew Details',
        TextCategory.button => 'Buttons & Actions',
        TextCategory.navigation => 'Navigation Labels',
      };

  String get description => switch (this) {
        TextCategory.header => 'Section titles like "Trending Now" and "Popular".',
        TextCategory.cardTitle => 'Movie and show titles below posters and in result grids.',
        TextCategory.body => 'Synopses, empty states, and other long-form app copy.',
        TextCategory.info => 'Year, runtime, genre chips, and similar metadata.',
        TextCategory.castDetails => 'Actor names under the cast row on a title\'s page.',
        TextCategory.button => 'Primary, outlined, and text button labels.',
        TextCategory.navigation => 'Bottom navigation and TV navigation-rail labels.',
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
  // --- The app's own two families ---
  AppFontChoice('instrument_serif', 'Instrument Serif (App Default Serif)', 'Instrument Serif'),
  AppFontChoice('space_grotesk', 'Space Grotesk (App Default Sans)', 'Space Grotesk'),

  // --- Elegant / luxury serifs ---
  AppFontChoice('cinzel', 'Cinzel (Luxury Display Serif)', 'Cinzel', previewWeight: FontWeight.w700),
  AppFontChoice('marcellus', 'Marcellus (Elegant Serif)', 'Marcellus'),
  AppFontChoice('playfair_display', 'Playfair Display (High-Contrast Serif)', 'Playfair Display', previewWeight: FontWeight.w600),
  AppFontChoice('cormorant_garamond', 'Cormorant Garamond (Refined Serif)', 'Cormorant Garamond', previewWeight: FontWeight.w600),
  AppFontChoice('dm_serif_display', 'DM Serif Display (Bold Poster Serif)', 'DM Serif Display'),

  // --- Cinematic display / condensed ---
  AppFontChoice('bebas_neue', 'Bebas Neue (Cinematic Condensed)', 'Bebas Neue'),
  AppFontChoice('anton', 'Anton (Heavy Poster Display)', 'Anton'),
  AppFontChoice('oswald', 'Oswald (Condensed Sans)', 'Oswald', previewWeight: FontWeight.w600),

  // --- Modern sans ---
  AppFontChoice('manrope', 'Manrope (Bright Modern Sans)', 'Manrope', previewWeight: FontWeight.w600),
  AppFontChoice('outfit', 'Outfit (Geometric Sans)', 'Outfit', previewWeight: FontWeight.w600),
  AppFontChoice('poppins', 'Poppins (Rounded Geometric Sans)', 'Poppins', previewWeight: FontWeight.w600),

  // --- Popular contemporary additions ---
  AppFontChoice('inter', 'Inter (Clean UI Sans)', 'Inter', previewWeight: FontWeight.w600),
  AppFontChoice('montserrat', 'Montserrat (Modern Geometric)', 'Montserrat', previewWeight: FontWeight.w600),
  AppFontChoice('lora', 'Lora (Warm Editorial Serif)', 'Lora'),
  AppFontChoice('roboto', 'Roboto (Classic UI Sans)', 'Roboto', previewWeight: FontWeight.w500),
  AppFontChoice('noto_sans', 'Noto Sans (Highly Legible Sans)', 'Noto Sans', previewWeight: FontWeight.w500),
  AppFontChoice('raleway', 'Raleway (Elegant Geometric)', 'Raleway', previewWeight: FontWeight.w600),
  AppFontChoice('nunito', 'Nunito (Friendly Rounded Sans)', 'Nunito', previewWeight: FontWeight.w600),
  AppFontChoice('quicksand', 'Quicksand (Soft Rounded Sans)', 'Quicksand', previewWeight: FontWeight.w600),
  AppFontChoice('rubik', 'Rubik (Readable Rounded Sans)', 'Rubik', previewWeight: FontWeight.w500),
  AppFontChoice('work_sans', 'Work Sans (Practical Sans)', 'Work Sans', previewWeight: FontWeight.w500),
  AppFontChoice('source_sans_3', 'Source Sans 3 (Humanist Sans)', 'Source Sans 3', previewWeight: FontWeight.w600),
  AppFontChoice('josefin_sans', 'Josefin Sans (Art-Deco Sans)', 'Josefin Sans', previewWeight: FontWeight.w600),
  AppFontChoice('libre_baskerville', 'Libre Baskerville (Classic Serif)', 'Libre Baskerville'),
  AppFontChoice('merriweather', 'Merriweather (Screen Serif)', 'Merriweather', previewWeight: FontWeight.w600),
  AppFontChoice('dm_sans', 'DM Sans (Modern Neutral Sans)', 'DM Sans', previewWeight: FontWeight.w500),

  // --- Script ---
  AppFontChoice('great_vibes', 'Great Vibes (Flowing Script)', 'Great Vibes'),
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
  // Neutrals
  Color(0xFFF5F5F7), // app default text (near-white)
  Color(0xFFFFFFFF), // pure white
  Color(0xFFB0B4C0), // cool gray
  Color(0xFF8A8F9C), // slate gray
  Color(0xFF000000), // jet black

  // Golds / warm metals - gold-1/2/3/4 mirror ark-theater-play-web's own
  // --gold-1..4 gradient shades (css/styles.css), so the app's accent
  // picker offers the same warm-gold range the reference web app's
  // buttons/highlights use.
  Color(0xFFE0A83A), // app default accent (metallic gold)
  Color(0xFFFFD27A), // gold-1 (lightest, ark-theater-play-web)
  Color(0xFFF6D68A), // warm champagne
  Color(0xFFD4AF37), // classic gold
  Color(0xFFE8C4A0), // soft copper
  Color(0xFFCD7F32), // bronze
  Color(0xFFFFB347), // gold-2 / amber (ark-theater-play-web)
  Color(0xFFE8891A), // gold-3 (ark-theater-play-web)
  Color(0xFF8A4A12), // gold-4 (deepest, ark-theater-play-web)

  // Reds / pinks
  Color(0xFFEF6B5A), // coral red
  Color(0xFFE0526B), // rose
  Color(0xFFE23E57), // cinema red
  Color(0xFFFF8FA3), // blush pink
  Color(0xFFFF5CA8), // hot pink

  // Purples / blues
  Color(0xFFC77DFF), // orchid
  Color(0xFF9D6BFF), // violet
  Color(0xFF7DA0FA), // periwinkle blue
  Color(0xFF4EA8DE), // azure
  Color(0xFF5AD1E0), // aqua
  Color(0xFF00E5D0), // turquoise

  // Greens / yellows
  Color(0xFF6BD08A), // mint green
  Color(0xFF3DDC84), // emerald
  Color(0xFFB8E05A), // lime
  Color(0xFFF2E863), // butter yellow
];
