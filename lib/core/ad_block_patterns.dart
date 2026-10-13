/// Ported from ARKVideoScrapper's `AD_HOST_PATTERNS`
/// (src/utils/adBlock.ts) — kept in sync manually. Used only by
/// WebViewPlayerScreen (the fallback path): when we have to show a
/// provider's real embed page, this is what keeps ad/tracker/popunder
/// scripts from ever loading in it.
final List<RegExp> adHostPatterns = [
  RegExp(r'doubleclick\.net$', caseSensitive: false),
  RegExp(r'googlesyndication\.com$', caseSensitive: false),
  RegExp(r'googletagmanager\.com$', caseSensitive: false),
  RegExp(r'google-analytics\.com$', caseSensitive: false),
  RegExp(r'adservice\.', caseSensitive: false),
  RegExp(r'popads\.net$', caseSensitive: false),
  RegExp(r'popcash\.net$', caseSensitive: false),
  RegExp(r'propellerads\.com$', caseSensitive: false),
  RegExp(r'propeller\.ads', caseSensitive: false),
  RegExp(r'adsterra\.com$', caseSensitive: false),
  RegExp(r'adnxs\.com$', caseSensitive: false),
  RegExp(r'taboola\.com$', caseSensitive: false),
  RegExp(r'outbrain\.com$', caseSensitive: false),
  RegExp(r'exoclick\.com$', caseSensitive: false),
  RegExp(r'juicyads\.com$', caseSensitive: false),
  RegExp(r'trafficjunky\.net$', caseSensitive: false),
  RegExp(r'clickadu\.com$', caseSensitive: false),
  RegExp(r'mgid\.com$', caseSensitive: false),
  RegExp(r'adskeeper\.co\.uk$', caseSensitive: false),
  RegExp(r'revcontent\.com$', caseSensitive: false),
  RegExp(r'smartadserver\.com$', caseSensitive: false),
  RegExp(r'media\.net$', caseSensitive: false),
  RegExp(r'adform\.net$', caseSensitive: false),
  RegExp(r'criteo\.(com|net)$', caseSensitive: false),
  RegExp(r'pubmatic\.com$', caseSensitive: false),
  RegExp(r'rubiconproject\.com$', caseSensitive: false),
  RegExp(r'bidswitch\.net$', caseSensitive: false),
  RegExp(r'onclickmega\.com$', caseSensitive: false),
  RegExp(r'adsco\.re$', caseSensitive: false),
  RegExp(r'highperformanceformat\.com$', caseSensitive: false),
  RegExp(r'^ads?\d*\.', caseSensitive: false),
  RegExp(r'(^|\.)ads\.', caseSensitive: false),
  RegExp(r'(^|\.)adsystem\.', caseSensitive: false),
  RegExp(r'(^|\.)track(ing)?\.', caseSensitive: false),
  RegExp(r'(^|\.)pixel\.', caseSensitive: false),
  RegExp(r'(^|\.)analytics\.', caseSensitive: false),
  RegExp(r'(^|\.)metrics\.', caseSensitive: false),
];

bool isAdOrTrackerHost(String host) {
  return adHostPatterns.any((re) => re.hasMatch(host));
}

/// Raw regex source strings, reused to build the WebView's `ContentBlocker`
/// rules (flutter_inappwebview) so ad/tracker sub-resources — scripts,
/// images, XHR — never load inside the embed page, not just top-level
/// navigations.
List<String> get adHostUrlFilters => adHostPatterns.map((re) => re.pattern).toList();

/// A deliberately narrow subset suitable for a WebView content blocker.
///
/// Brave's filter engine has enough context to apply large rule lists without
/// breaking page bootstraps. WKWebView/Android WebView content rules do not:
/// broad hostname patterns can accidentally block a provider's required
/// script and leave the player blank. These are high-confidence, third-party
/// ad-network URL rules shared by the embedded player on every platform.
const embedSafeAdUrlFilters = <String>[
  r'^https?://([^/]+\.)?doubleclick\.net/',
  r'^https?://([^/]+\.)?googlesyndication\.com/',
  r'^https?://([^/]+\.)?adservice\.google\.',
  r'^https?://([^/]+\.)?popads\.net/',
  r'^https?://([^/]+\.)?popcash\.net/',
  r'^https?://([^/]+\.)?propellerads\.com/',
  r'^https?://([^/]+\.)?adsterra\.com/',
  r'^https?://([^/]+\.)?exoclick\.com/',
  r'^https?://([^/]+\.)?trafficjunky\.net/',
  r'^https?://([^/]+\.)?clickadu\.com/',
  r'^https?://([^/]+\.)?onclickmega\.com/',
];
