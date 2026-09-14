/// Shared (TMDB language code, display label) list used by Home's
/// per-language rows. Deliberately kept small: each entry costs Home two
/// extra `/discover` calls (movie + tv) on *every* load, all sharing this
/// project's public demo TMDB api_key with however many other installs of
/// this same open-source app - widening this list widens Home's own
/// request burst on every single visit. Use [kBrowseLanguages] instead for
/// anything that only fetches on demand (filter chips/dropdowns), which is
/// safe to make much longer.
const kLanguages = [
  ('en', 'English'),
  ('ta', 'Tamil'),
  ('te', 'Telugu'),
  ('kn', 'Kannada'),
  ('ml', 'Malayalam'),
  ('hi', 'Hindi'),
  ('ko', 'Korean'),
  ('ja', 'Japanese'),
];

/// Fuller (TMDB language code, display label) list for the Movies/TV Shows
/// browse filters and the Search screen's language filter. Unlike
/// [kLanguages], picking one of these only fires a single request (or a
/// client-side filter) at the moment the user selects it, so it's safe for
/// this list to be much longer. Superset of [kLanguages] plus more Indian
/// regional languages, Turkish (ARKVideoScrapper now has dedicated Turkish
/// provider coverage - see providers/yoturkish.ts), and other widely
/// requested languages.
const kBrowseLanguages = [
  ('en', 'English'),
  ('ta', 'Tamil'),
  ('te', 'Telugu'),
  ('kn', 'Kannada'),
  ('ml', 'Malayalam'),
  ('hi', 'Hindi'),
  ('bn', 'Bengali'),
  ('mr', 'Marathi'),
  ('pa', 'Punjabi'),
  ('gu', 'Gujarati'),
  ('ur', 'Urdu'),
  ('ko', 'Korean'),
  ('ja', 'Japanese'),
  ('zh', 'Chinese'),
  ('th', 'Thai'),
  ('id', 'Indonesian'),
  ('tl', 'Tagalog'),
  ('tr', 'Turkish'),
  ('es', 'Spanish'),
  ('fr', 'French'),
  ('de', 'German'),
  ('it', 'Italian'),
  ('pt', 'Portuguese'),
  ('ru', 'Russian'),
  ('ar', 'Arabic'),
];
