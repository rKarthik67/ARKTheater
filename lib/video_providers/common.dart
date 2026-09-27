import '../core/languages.dart';

/// Shared result shapes for every stream provider (scraper-API-backed or
/// direct), ported from flixquest's `lib/video_providers/common.dart` so the
/// player and provider loader can treat every source identically regardless
/// of where it came from.
class RegularVideoLinks {
  String? url;
  String? quality;
  String? server;
  bool? isM3U8;
  bool? isDash;
  Map<String, String>? headers;
  String? sizeToken;

  RegularVideoLinks({
    this.url,
    this.quality = 'unknown quality',
    this.server,
    this.isM3U8,
    this.isDash,
    this.headers,
    this.sizeToken,
  });

  RegularVideoLinks.fromJson(Map<String, dynamic> json) {
    url = json['url'] as String?;
    server = json['server']?.toString();
    quality = json.containsKey('quality') ? json['quality'] as String? : 'unknown quality';
    isM3U8 = json['isM3U8'] as bool?;
    isDash = json['isDASH'] as bool?;
    sizeToken = json['sizeToken']?.toString();
    final rawHeaders = json['headers'];
    if (rawHeaders is Map) {
      headers = {
        for (final entry in rawHeaders.entries)
          if (entry.value is String) entry.key.toString(): entry.value as String,
      };
    }
  }
}

/// Providers expose the selected dub in their server label. Keep the parsing
/// in one place so every player surface can offer the same audio switcher.
/// Human-readable audio-track label for one link, derived from whatever
/// the scraper put in `server`.
///
/// Every provider spells this differently, and the formats drift whenever
/// the scraper changes - which is exactly how this silently regressed to
/// "Default" for everything: Castle moved from "Castle · English" to a
/// "castle-english-1" slug, and VidSync only falls back to its own
/// "VidSync | ... | <language> | n" format when the upstream source didn't
/// supply a `server` of its own. So each known shape is matched
/// explicitly, and anything unrecognised gets one last pass looking for a
/// known language name anywhere in the string before giving up.
String audioLabelForLink(RegularVideoLinks link) {
  final server = (link.server ?? '').trim();
  if (server.isEmpty) return 'Default';
  final lower = server.toLowerCase();

  // VidSync: "VidSync | <upstream provider> | <language> | <n>"
  if (lower.startsWith('vidsync')) {
    final parts = server.split('|').map((part) => part.trim()).toList();
    if (parts.length >= 3 && parts[2].isNotEmpty) return _titleCaseLabel(parts[2]);
  }

  // Castle, older builds: "Castle · English" (also tolerate a pipe).
  if (lower.startsWith('castle ·') || lower.startsWith('castle |')) {
    final sep = server.indexOf(RegExp(r'[·|]'));
    if (sep != -1) {
      final label = server.substring(sep + 1).trim();
      if (label.isNotEmpty) return _titleCaseLabel(label);
    }
  }

  // Castle, current builds: "castle-english-1", "castle-brazilian-portuguese-2".
  final castle = RegExp(r'^castle[-_](.+?)[-_](\d+)$', caseSensitive: false).firstMatch(server);
  final castleLanguage = castle?.group(1);
  if (castleLanguage != null && castleLanguage.isNotEmpty) {
    return _titleCaseLabel(castleLanguage);
  }

  if (lower.startsWith('kisskh')) return 'Original audio';

  // Unrecognised shape - a provider's own server string, or a format that
  // changed again. Pick out a known language name if one is in there.
  final detected = _languageNameIn(server);
  if (detected != null) return detected;

  return 'Default';
}

/// Tidies one extracted audio label: "brazilian-portuguese" -> "Brazilian
/// Portuguese", "ENGLISH" -> "English", and a bare language code -> its
/// full name.
///
/// That last case is not hypothetical: Castle falls back to
/// `track.abbreviate` when `languageName` is missing, and VidSync to
/// `track.language`, so a track can arrive labelled "ta" or "te". Showing
/// "Ta" in the switcher is useless, and kBrowseLanguages already pairs
/// every code with its name.
String _titleCaseLabel(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[_-]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.isEmpty) return 'Default';

  final lower = cleaned.toLowerCase();
  for (final (code, label) in kBrowseLanguages) {
    if (lower == code) return label;
  }
  return cleaned
      .split(' ')
      .map((word) => word.isEmpty
          ? word
          : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
      .join(' ');
}

/// Longest known language name appearing as a whole word in [haystack],
/// or null. Longest-match so "Brazilian Portuguese" beats "Portuguese".
String? _languageNameIn(String haystack) {
  final lower = haystack.toLowerCase();
  String? best;
  for (final (_, label) in kBrowseLanguages) {
    final name = label.toLowerCase();
    if (!RegExp('\\b${RegExp.escape(name)}\\b').hasMatch(lower)) continue;
    if (best == null || name.length > best.length) best = label;
  }
  return best;
}

List<String> audioLabelsForLinks(List<RegularVideoLinks> links) {
  return links.map(audioLabelForLink).toSet().toList();
}

class RegularSubtitleLinks {
  String? url;
  String? language;
  Map<String, String>? headers;

  RegularSubtitleLinks({this.language, this.url, this.headers});

  RegularSubtitleLinks.fromJson(Map<String, dynamic> json) {
    url = (json['url'] ?? json['file']) as String?;
    language = (json['lang'] ?? json['label']) as String?;
    final rawHeaders = json['headers'];
    if (rawHeaders is Map) {
      headers = {
        for (final entry in rawHeaders.entries)
          if (entry.value is String) entry.key.toString(): entry.value as String,
      };
    }
  }
}

/// The normalized result returned by every in-app stream provider - direct
/// (VixSrc) or scraper-API-backed alike - so the player and DetailScreen
/// use one contract regardless of source.
class ProviderLoadResult {
  const ProviderLoadResult({
    this.videoLinks,
    this.subtitleLinks,
    this.success = false,
    this.errorMessage,
  });

  final List<RegularVideoLinks>? videoLinks;
  final List<RegularSubtitleLinks>? subtitleLinks;
  final bool success;
  final String? errorMessage;
}
