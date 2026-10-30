import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_fonts.dart';
import '../state/settings_provider.dart';

/// Visual identity: color palette borrowed from the C.L.A.R.A. desktop
/// app's "dark gold" design system (D:\CLARA\apps\desktop\ui\index.html),
/// combined with reflixmovies.vercel.app's typography and text colors -
/// Instrument Serif for display/headline text, Space Grotesk for body/UI
/// text, with Reflix's off-white/gray text colors sitting on top of
/// C.L.A.R.A.'s near-black, warm-bordered surfaces and metallic gold
/// accent. Menu-like surfaces (nav bars, sheets, player controls) layer a
/// frosted "liquid glass" material on top - see widgets/liquid_glass.dart.
///
/// Both font families are bundled locally under assets/fonts/ (declared in
/// pubspec.yaml) instead of using the google_fonts package's default
/// runtime-fetch behavior - that package downloads each font from
/// fonts.gstatic.com on first use and silently falls back to the system
/// font if that fetch fails, which is exactly what a slow or ISP-blocked
/// connection produces: no crash, no error, just plain-looking text that
/// never explains why the "different font styles" aren't visible.
/// Bundling the .ttf files means the fonts always render, offline or not.
///
/// User customization: the app's accent color and three named text
/// categories (see [TextCategory] in app_fonts.dart) can be overridden per
/// user from the Settings screen's "Fonts & Colors" / "App Theme" sections,
/// persisted in [SettingsProvider]. [themeFor] builds the live ThemeData
/// from whatever accent is currently chosen; [resolvedStyle] layers a
/// category's font/color override on top of one of the named TextStyles
/// below. Both fall back to this class's original constants when the user
/// hasn't customized anything, so the app looks exactly as before out of
/// the box.
class AppTheme {
  AppTheme._();

  static const String serifFont = 'Instrument Serif';
  static const String sansFont = 'Space Grotesk';

  // --- Surfaces (aligned with ARK Play's charcoal liquid-glass palette) ---
  static const Color background = Color(0xFF08090D);
  static const Color surface = Color(0xFF101116);
  static const Color surfaceVariant = Color(0xFF12141A);
  static const Color surfaceTertiary = Color(0xFF1A1C23);

  // --- Borders (C.L.A.R.A.'s --line/--line-warm) ---
  static const Color border = Color(0xFF292C34);
  static const Color borderWarm = Color(0xFF3A3E49);

  // --- Accent: C.L.A.R.A.'s metallic gold (--gold family) - the app's
  // *default* accent. A user-chosen accent (SettingsProvider.accentColor)
  // overrides this in themeFor()'s ColorScheme/component themes, but this
  // constant stays as the fallback and is still what a handful of widgets
  // reference directly for one-off highlights that aren't Theme-driven. ---
  static const Color accent = Color(0xFFE0A83A);
  static const Color accentHigh = Color(0xFFF6D68A);
  static const Color accentLow = Color(0xFFA9761C);
  static const Color accentDim = Color(0xFF4A3A18);
  static const Color accentGlow = Color(0x38E0A83A);

  /// Dark text C.L.A.R.A. sets on top of its gold buttons - not just
  /// black, a warm near-black that reads better against the gold gradient.
  static const Color goldText = Color(0xFF221703);

  // --- Semantic (C.L.A.R.A.'s --ok/--warn/--err) ---
  static const Color success = Color(0xFF8FB84A);
  static const Color warning = Color(0xFFE0A83A);
  static const Color error = Color(0xFFE06A52);

  // --- Text (reflixmovies.vercel.app's --foreground/muted) ---
  static const Color textPrimary = Color(0xFFF5F5F7);
  static const Color textSecondary = Color(0xFFA8A5A0);

  // --- Light palette (Settings > Appearance > Light, Watchly-style clean
  // white look). Dark stays the app's default; this only applies once a
  // user opts into ThemeMode.light. ---
  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFF1F1F4);
  static const Color lightSurfaceTertiary = Color(0xFFE7E7EC);
  static const Color lightBorder = Color(0xFFE2E2E8);
  static const Color lightBorderWarm = Color(0xFFD3D3DC);
  static const Color lightTextPrimary = Color(0xFF14161A);
  static const Color lightTextSecondary = Color(0xFF55585F);

  static bool _isLight(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  /// Brightness-aware reads of the surface/text constants above, for the
  /// handful of widgets that paint with them directly instead of through
  /// Theme.of(context) - see [themeFor]'s doc comment. Call sites that
  /// already read Theme.of(context)/textTheme (buttons, Card, AppBar,
  /// Divider, default body text) don't need these; they already follow
  /// ThemeData's own light/dark branch below.
  static Color backgroundOf(BuildContext context) =>
      _isLight(context) ? lightBackground : background;
  static Color surfaceOf(BuildContext context) =>
      _isLight(context) ? lightSurface : surface;
  static Color surfaceVariantOf(BuildContext context) =>
      _isLight(context) ? lightSurfaceVariant : surfaceVariant;
  static Color surfaceTertiaryOf(BuildContext context) =>
      _isLight(context) ? lightSurfaceTertiary : surfaceTertiary;
  static Color borderOf(BuildContext context) =>
      _isLight(context) ? lightBorder : border;
  static Color borderWarmOf(BuildContext context) =>
      _isLight(context) ? lightBorderWarm : borderWarm;
  static Color textPrimaryOf(BuildContext context) =>
      _isLight(context) ? lightTextPrimary : textPrimary;
  static Color textSecondaryOf(BuildContext context) =>
      _isLight(context) ? lightTextSecondary : textSecondary;

  // --- Named text styles for different kinds of information, so a title,
  // a synopsis, a metadata line and a badge never look interchangeable
  // even when they sit right next to each other. ---

  /// Section/row headers ("Trending Now", "Popular", genre rail titles) -
  /// Instrument Serif with a touch of letter-spacing, distinct from the
  /// plain Space Grotesk body copy sitting directly below it in the row.
  /// Takes [context] (unlike the other named styles below) because, unlike
  /// [cardTitleStyle]/[heroTitleStyle], it sits on the plain page
  /// background rather than over poster/backdrop art, so it has to follow
  /// the light/dark theme rather than always being light-on-dark.
  static TextStyle sectionHeaderStyle(BuildContext context) => TextStyle(
        fontFamily: serifFont,
        fontSize: 21,
        fontWeight: FontWeight.w500,
        color: textPrimaryOf(context),
        letterSpacing: 0.2,
      );

  /// Poster/media card titles - Space Grotesk, a little heavier than plain
  /// body text so a whole grid of cards still reads as titles first.
  static const TextStyle cardTitleStyle = TextStyle(
    fontFamily: sansFont,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  /// Small metadata under a title - year, episode tag, runtime, genre list
  /// - always muted, always a size down from the title it sits under. Takes
  /// [context] for the same reason as [sectionHeaderStyle]: it's plain page
  /// text, not text painted over art.
  static TextStyle metaStyle(BuildContext context) => TextStyle(
        fontFamily: sansFont,
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: textSecondaryOf(context),
      );

  /// Hero banner / detail-screen title - the largest, most cinematic text
  /// in the app - Instrument Serif, matching reflixmovies.vercel.app's h1.
  static const TextStyle heroTitleStyle = TextStyle(
    fontFamily: serifFont,
    fontSize: 30,
    fontWeight: FontWeight.w400,
    color: textPrimary,
    height: 1.05,
  );

  /// Hero banner / detail-screen synopsis - Space Grotesk, muted, sits
  /// directly under [heroTitleStyle].
  static const TextStyle heroOverviewStyle = TextStyle(
    fontFamily: sansFont,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    height: 1.35,
  );

  /// Small pill/badge text (rating chips, "NEW" tags, provider badges) -
  /// bold with a little tracking, dark-on-gold by default so it reads on
  /// the accent background it's usually pinned to.
  static const TextStyle badgeStyle = TextStyle(
    fontFamily: sansFont,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: goldText,
    letterSpacing: 0.3,
  );

  /// Cast & crew name text under the cast row's avatar on the detail
  /// screen - plain Space Grotesk by default, its own customizable
  /// category ([TextCategory.castDetails]) since it sits so close to a
  /// person's photo that a mismatched font reads oddly fast. Sits on the
  /// plain page background (not over the avatar photo), so - like
  /// [sectionHeaderStyle]/[metaStyle] - it takes [context] to follow theme.
  static TextStyle castNameStyle(BuildContext context) => TextStyle(
        fontFamily: sansFont,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: textPrimaryOf(context),
      );

  /// C.L.A.R.A.'s `--shine` gradient - the metallic gold sheen it uses for
  /// primary buttons and gradient-clipped brand text.
  static const LinearGradient shine = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentHigh, accent, accentLow],
    stops: [0.0, 0.42, 1.0],
  );

  /// Layers a [TextCategory]'s user-chosen font family + color (from
  /// Settings > Fonts & Colors) on top of [base]. Falls back to [base]
  /// untouched wherever the user hasn't customized that category - so
  /// every call site keeps working exactly as before until someone opts
  /// in. Safe to call without a [SettingsProvider] ancestor (returns
  /// [base] unchanged, e.g. in a widget test).
  static TextStyle resolvedStyle(BuildContext context, TextStyle base, TextCategory category) {
    SettingsProvider? settings;
    try {
      settings = context.watch<SettingsProvider>();
    } catch (_) {
      return base;
    }
    final font = settings.fontChoiceFor(category);
    final color = settings.fontColorFor(category);
    if (font == null && color == null) return base;
    return base.copyWith(
      fontFamily: font?.fontFamily,
      // A custom font family with no matching weight file for the base
      // style's fontWeight would otherwise ask the engine for a weight it
      // doesn't have; clearing it lets each bundled family fall back to
      // its own normal weight instead of a silently-substituted one.
      fontWeight: font != null ? FontWeight.w500 : base.fontWeight,
      color: color ?? base.color,
    );
  }

  static TextStyle _configuredStyle(TextStyle base, SettingsProvider? settings, TextCategory category) {
    final font = settings?.fontChoiceFor(category);
    final color = settings?.fontColorFor(category);
    if (font == null && color == null) return base;
    return base.copyWith(
      fontFamily: font?.fontFamily,
      fontWeight: font != null ? FontWeight.w500 : base.fontWeight,
      color: color ?? base.color,
    );
  }

  /// The live accent color: the user's Settings > App Theme choice if set,
  /// otherwise [accent].
  static Color resolvedAccent(BuildContext context) {
    try {
      return context.watch<SettingsProvider>().accentColor ?? accent;
    } catch (_) {
      return accent;
    }
  }

  /// Space Grotesk for body/UI text, Instrument Serif for display and
  /// headline slots (including AppBar titles, which default to
  /// `titleLarge`) - mirrors reflixmovies.vercel.app exactly, which pairs
  /// the same two families the same way.
  static TextTheme _textTheme(TextTheme base) {
    final body = base.apply(fontFamily: sansFont);
    const serif = TextStyle(fontFamily: serifFont);
    return body.copyWith(
      displayLarge: body.displayLarge?.merge(serif),
      displayMedium: body.displayMedium?.merge(serif),
      displaySmall: body.displaySmall?.merge(serif),
      headlineLarge: body.headlineLarge?.merge(serif),
      headlineMedium: body.headlineMedium?.merge(serif),
      headlineSmall: body.headlineSmall?.merge(serif),
      titleLarge: body.titleLarge?.merge(serif),
    );
  }

  /// Builds the app's ThemeData with [accentColor] (defaults to the app's
  /// own gold [accent]) driving every Material-component color that reads
  /// from the ColorScheme/component themes below: buttons, the slider,
  /// selected nav rail/bottom-nav items, and the AppBar. A handful of
  /// widgets elsewhere in the app paint with the [accent] constant
  /// directly rather than through Theme.of(context) and won't repaint
  /// from this - see the Settings screen's "App Theme" section note.
  ///
  /// [brightness] picks the dark (default, unchanged from before this
  /// param existed) or light palette - see [lightBackground] etc. Both
  /// branches build through the exact same component-theme structure below
  /// so buttons/nav/dividers/popups stay visually consistent across the
  /// toggle, just recolored.
  static ThemeData themeFor({
    Color accentColor = accent,
    SettingsProvider? settings,
    Brightness brightness = Brightness.dark,
  }) {
    final isLight = brightness == Brightness.light;
    final base = isLight
        ? ThemeData.light(useMaterial3: true)
        : ThemeData.dark(useMaterial3: true);
    final baseBackground = isLight ? lightBackground : background;
    final baseSurface = isLight ? lightSurface : surface;
    final baseSurfaceVariant = isLight ? lightSurfaceVariant : surfaceVariant;
    final baseSurfaceTertiary = isLight ? lightSurfaceTertiary : surfaceTertiary;
    final baseBorder = isLight ? lightBorder : border;
    final baseBorderWarm = isLight ? lightBorderWarm : borderWarm;
    final basePrimaryText = isLight ? lightTextPrimary : textPrimary;
    final baseSecondaryText = isLight ? lightTextSecondary : textSecondary;

    // ARK Play mixes the selected accent into all of its surfaces, not only
    // buttons. Mirror that here so changing Accent Color recolors the
    // complete Material shell - lighter mix on the light palette so a
    // strong accent doesn't muddy an otherwise clean white background.
    final themedBackground =
        Color.lerp(baseBackground, accentColor, isLight ? 0.035 : 0.09)!;
    final themedSurface =
        Color.lerp(baseSurface, accentColor, isLight ? 0.05 : 0.13)!;
    final themedSurfaceVariant =
        Color.lerp(baseSurfaceVariant, accentColor, isLight ? 0.07 : 0.19)!;
    final themedBorder =
        Color.lerp(baseBorder, accentColor, isLight ? 0.18 : 0.35)!;
    final themedSurfaceTertiary =
        Color.lerp(baseSurfaceTertiary, accentColor, isLight ? 0.06 : 0.16)!;
    final defaultTextTheme = _textTheme(base.textTheme).apply(
      bodyColor: basePrimaryText,
      displayColor: basePrimaryText,
    );
    final bodyStyle = _configuredStyle(
      TextStyle(fontFamily: sansFont, color: basePrimaryText),
      settings,
      TextCategory.body,
    );
    final textTheme = defaultTextTheme.copyWith(
      bodyLarge: defaultTextTheme.bodyLarge?.merge(bodyStyle),
      bodyMedium: defaultTextTheme.bodyMedium?.merge(bodyStyle),
      bodySmall: defaultTextTheme.bodySmall?.merge(bodyStyle),
    );
    final buttonTextStyle = _configuredStyle(
      const TextStyle(fontFamily: sansFont, fontWeight: FontWeight.w600),
      settings,
      TextCategory.button,
    );
    final selectedNavigationStyle = _configuredStyle(
      TextStyle(fontFamily: sansFont, color: accentColor, fontWeight: FontWeight.w600),
      settings,
      TextCategory.navigation,
    );
    final unselectedNavigationStyle = _configuredStyle(
      TextStyle(fontFamily: sansFont, color: baseSecondaryText),
      settings,
      TextCategory.navigation,
    );
    final glow = accentColor.withOpacity(0.22);

    return base.copyWith(
      scaffoldBackgroundColor: themedBackground,
      colorScheme: base.colorScheme.copyWith(
        primary: accentColor,
        secondary: accentColor,
        surface: themedSurface,
        surfaceVariant: themedSurfaceVariant,
        onSurface: basePrimaryText,
        error: error,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: basePrimaryText,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: basePrimaryText),
      ),
      cardColor: themedSurface,
      dividerColor: themedBorder,
      textTheme: textTheme,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: goldText,
          textStyle: buttonTextStyle,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: basePrimaryText,
          side: BorderSide(color: baseBorderWarm),
          textStyle: buttonTextStyle,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentColor,
          textStyle: buttonTextStyle,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: themedSurfaceVariant.withOpacity(0.92),
        surfaceTintColor: Colors.transparent,
        textStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: baseBorder),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        modalBackgroundColor: Colors.transparent,
        elevation: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        selectedIconTheme: IconThemeData(color: accentColor),
        unselectedIconTheme: IconThemeData(color: baseSecondaryText),
        selectedLabelTextStyle: selectedNavigationStyle,
        unselectedLabelTextStyle: unselectedNavigationStyle,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: accentColor,
        unselectedItemColor: baseSecondaryText,
        selectedLabelStyle: selectedNavigationStyle,
        unselectedLabelStyle: unselectedNavigationStyle,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accentColor,
        thumbColor: accentColor,
        inactiveTrackColor: themedBorder,
        overlayColor: glow,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: themedSurfaceTertiary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: basePrimaryText),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// The app's default-accent theme - unchanged behavior for any call site
  /// that doesn't need to react to the user's chosen accent color.
  static ThemeData get dark => themeFor();
}
