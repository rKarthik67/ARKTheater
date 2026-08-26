# ARKTheater

A movie & TV streaming app (Flutter/Dart) that browses via TMDB, resolves
ad-free direct video sources through **ARKVideoScrapper**, and plays them in
a native player — no iframes, no ad scripts, no popups. One codebase targets
phone, tablet, desktop (Windows/Linux), macOS, and iPad/iPadOS.

Reference: the UI/flows are modeled on the existing React web app
(`Movie-and-tv-show-2`) — TMDB-driven browse/search/detail, a watchlist, a
"Play" action per title — but instead of the web app's ad-laden `<iframe>`
embeds (`vidsrc`, `videasy`, etc. loaded directly in the page), this app
never loads a provider page at all (except as an explicit last-resort
fallback, see below). It calls ARKVideoScrapper, which does that scraping
and hands back only the clean stream URL.

The stream-resolution client (`lib/video_providers/`) is ported from
[flixquest](https://github.com/BeamlakAschalew/flixquest)'s own
`video_providers/` module (GPL-3.0), at the user's explicit request to
follow that app's architecture closely: it fetches ARKVideoScrapper's live
provider catalog, races providers in ordered batches of three via
`ProviderLoader.loadFirstSuccessful` so a slow/dead provider never blocks a
working one, and falls back to a direct VixSrc provider that needs no
backend at all if the scraper is unreachable. One deliberate difference
from flixquest: its own player is built on `better_player_plus`, which only
ships Android/iOS support - adopting it here would silently drop the
Windows/macOS/Linux/iPadOS desktop targets this app was built for from day
one, so `PlayerScreen` stays on `media_kit` (the one engine that actually
plays natively everywhere) with a custom control surface on top: server
switching, quality switching, subtitle track picker, playback speed, and
10s skip forward/back.

**WebView fallback.** If every provider fails to resolve (`PlayerScreen`'s
"Try another source" is exhausted, or nothing loads at all), `PlayerScreen`
and `DetailScreen` both offer "Watch via embedded player" -
`WebViewPlayerScreen` renders a provider's real embed page in an
app-controlled, ad-blocked `flutter_inappwebview` view (popups disabled at
the WebView-settings level, known ad/tracker hosts blocked via
`ContentBlocker` rules mirroring ARKVideoScrapper's own patterns). It's not
as clean as native extraction, but it means the app never dead-ends.

## Architecture

```
lib/
  core/             theme, responsive breakpoints, env config, embed-URL
                     builders + ad-host patterns for the WebView fallback
  models/           MediaItem, MediaDetail, PersonDetail
  video_providers/  ported from flixquest: VideoProvider/VideoProviderType,
                     ScraperApi (ARKVideoScrapper /api/v2 client), VixSrc
                     (direct fallback provider), ProviderLoader (batched,
                     ordered fallback racing), ProviderLoadResult/
                     RegularVideoLinks/RegularSubtitleLinks (shared result
                     shapes both provider kinds return)
  services/         TmdbService (browse/search/detail), WatchlistService
  state/            WatchlistProvider (ChangeNotifier)
  screens/          HomeScreen, SearchScreen, DetailScreen, PlayerScreen,
                     WebViewPlayerScreen (fallback), PersonDetailScreen,
                     WatchlistScreen
  widgets/          MediaCard, MediaRow, ResponsiveScaffold (bottom nav <->
                     nav rail), etc.
```

Playback uses [`media_kit`](https://pub.dev/packages/media_kit), which gives
one native playback code path across Android, iOS, macOS, Windows, and
Linux (unlike `video_player`, whose desktop support is inconsistent) — this
is what makes "same app, every platform" realistic here.

## Requirements

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.19+ (stable channel)
- For iOS/iPadOS/macOS builds: a Mac with Xcode
- For Windows builds: Windows with Visual Studio (Desktop development with C++ workload)
- For Android: Android Studio / an Android SDK
- A running instance of **ARKVideoScrapper** (see its own README) — this app
  is the client, the scraper is the server it talks to.

## First-time setup

This repo ships with `lib/`, `pubspec.yaml`, and config already written, but
**not** the generated native platform folders (`android/`, `ios/`,
`macos/`, `windows/`, `linux/`) — those are large, auto-generated, and
regenerate cleanly from the Flutter SDK, so they're created on your machine
instead of being hand-committed:

```bash
cd ARKTheater
flutter create . --platforms=android,ios,macos,windows,linux --org com.ark.theater
```

This is safe to run on top of the existing project: it only fills in the
missing platform folders and leaves `lib/`, `pubspec.yaml`, and everything
else untouched. (There's no separate "iPad" platform target — the `ios`
platform covers iPhone and iPad; the app's responsive layout in
`core/responsive.dart` already adapts the UI for iPad's larger screen the
same way it adapts for Android tablets and desktop.)

Then:

```bash
cp .env.example .env      # already done for you with the default TMDB key —
                           # edit SCRAPER_BASE_URL to point at your deployed scraper
flutter pub get
flutter run                # pick a connected device/simulator, or:
flutter run -d macos
flutter run -d windows
flutter run -d linux
flutter run -d chrome      # media_kit playback isn't supported on web yet — browse/search only
```

## How playback works end-to-end

1. `DetailScreen` fetches ARKVideoScrapper's provider catalog
   (`ScraperApi.getProviders()`) once, and appends the direct `VixSrc`
   provider as a last entry that doesn't need the scraper at all.
2. On "Play", `ProviderLoader.loadFirstSuccessful` races those providers in
   ordered batches of three - each scraper-backed provider resolves via one
   HTTP call to `ARKVideoScrapper`'s `/api/v2/stream-movie` or
   `/api/v2/stream-tv` (which itself decodes the source site's own API
   rather than driving a browser), while `VixSrc` talks to vixsrc.to
   directly. The first batch member to return a playable link wins, so a
   slow or dead provider never blocks a working one.
3. `PlayerScreen` hands the winning `RegularVideoLinks.url` straight to
   `media_kit`'s `Player`, with the CDN-required headers attached. The
   top-right menu bar lets you switch subtitles, playback speed, quality
   (other `RegularVideoLinks` in the same result), or server (re-resolves a
   different `VideoProvider` on demand) without leaving the player.
4. If every provider fails (or a resolved link won't actually play - a
   single-use token, a fingerprint-mismatched CDN), both `DetailScreen` and
   `PlayerScreen` offer "Watch via embedded player": `WebViewPlayerScreen`
   renders a provider's real page in an ad-blocked, popup-blocked
   `flutter_inappwebview` view instead of leaving the user with nothing.

Nothing from a provider's own web page — ad scripts, popunders, tracking
pixels, the iframe itself — reaches the app on the native path (steps 1-3);
the fallback path (step 4) is the one deliberate exception, scoped as
narrowly as possible and blocked at both the popup and ad-host level.

## Extending

- **New browse rows / filters** (e.g. the reference app's language-specific
  rows for Hindi/Tamil/Telugu/Kannada/Malayalam): add a method to
  `TmdbService` using TMDB's `discover` endpoint with `with_original_language`,
  then a new `MediaRow` in `HomeScreen`.
- **Continue watching / resume position**: `media_kit`'s `Player.stream.position`
  can be persisted the same way `WatchlistService` persists bookmarks.
- **Download-for-offline**: out of scope for this pass, but `media_kit` streams
  are standard HLS, so an HLS-to-local-file downloader can be layered on later.
