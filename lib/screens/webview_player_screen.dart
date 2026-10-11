import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../core/ad_block_patterns.dart';
import '../core/embed_providers.dart';
import '../core/theme.dart';
import '../models/media_item.dart';

/// Last-resort fallback for when every native provider fails: renders a
/// provider's real embed page in an app-controlled WebView instead of
/// leaving the user with a dead end.
///
/// This can't guarantee zero ads the way native extraction does (some ad
/// creative is served from the same host as the player and isn't
/// distinguishable from it), but it:
///   - blocks window.open()/target=_blank popups outright, and
///   - blocks requests to known ad/tracker/popunder hosts before they load,
///     via ContentBlocker rules mirroring ARKVideoScrapper's own
///     AD_HOST_PATTERNS (see ad_block_patterns.dart).
class WebViewPlayerScreen extends StatefulWidget {
  const WebViewPlayerScreen({
    super.key,
    required this.title,
    required this.type,
    required this.tmdbId,
    this.season,
    this.episode,
    this.initialProviderIndex = 0,
  });

  final String title;
  final MediaType type;
  final int tmdbId;
  final int? season;
  final int? episode;
  final int initialProviderIndex;

  @override
  State<WebViewPlayerScreen> createState() => _WebViewPlayerScreenState();
}

class _WebViewPlayerScreenState extends State<WebViewPlayerScreen> {
  InAppWebViewController? _controller;
  late int _providerIndex;
  bool _loading = true;

  static final List<ContentBlocker> _contentBlockers = [
    for (final pattern in adHostUrlFilters)
      ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: pattern),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
      ),
  ];

  EmbedProvider get _provider => embedProviders[_providerIndex];

  String get _url =>
      _provider.urlFor(widget.type, widget.tmdbId, season: widget.season, episode: widget.episode);

  /// Embed pages can load video, subtitles, and scripts from other hosts, so
  /// those subresources must remain available. A full-page navigation is
  /// different: it is almost always a click-through/popunder when it leaves
  /// the selected embed's site. Keep that navigation inside the provider.
  bool _isSelectedEmbedHost(String host) {
    final selectedHost = WebUri(_url).host.toLowerCase();
    final candidate = host.toLowerCase();
    return candidate == selectedHost || candidate.endsWith('.$selectedHost');
  }

  @override
  void initState() {
    super.initState();
    _providerIndex = widget.initialProviderIndex.clamp(0, embedProviders.length - 1);
  }

  void _switchProvider(int index) {
    if (index == _providerIndex) return;
    setState(() {
      _providerIndex = index;
      _loading = true;
    });
    _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(_url)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        // AppBar automatically honours the iPad safe area, including the
        // compact/Stage Manager window controls. An explicit leading button
        // keeps the app back action in that protected header rather than in
        // the provider's web content.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to details',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('${widget.title} · ${_provider.name}', overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.dns_outlined),
            tooltip: 'Switch server',
            onSelected: _switchProvider,
            itemBuilder: (context) => [
              for (var i = 0; i < embedProviders.length; i++)
                PopupMenuItem(
                  value: i,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (i == _providerIndex)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.check, size: 16, color: AppTheme.accent),
                        ),
                      Text(embedProviders[i].name),
                    ],
                  ),
                ),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _controller?.reload()),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_url)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              // The single biggest popup-blocking lever: without this, a
              // page's window.open()/target=_blank calls cannot spawn a
              // second window/tab at all, on either platform.
              javaScriptCanOpenWindowsAutomatically: false,
              supportMultipleWindows: false,
              useShouldOverrideUrlLoading: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              disallowOverScroll: true,
              contentBlockers: _contentBlockers,
              userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
            ),
            onWebViewCreated: (controller) => _controller = controller,
            onLoadStart: (controller, url) {
              if (mounted) setState(() => _loading = true);
            },
            onLoadStop: (controller, url) async {
              if (mounted) setState(() => _loading = false);
            },
            // Extra safety net on top of supportMultipleWindows: false -
            // some platforms still route certain popups through here.
            // Returning false tells the plugin not to create a window for
            // it at all.
            onCreateWindow: (controller, createWindowAction) async => false,
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final uri = navigationAction.request.url;
              if (uri == null) return NavigationActionPolicy.CANCEL;
              if (isAdOrTrackerHost(uri.host)) {
                return NavigationActionPolicy.CANCEL;
              }

              // Do not let a clicked ad replace the whole embedded player.
              // Iframes and media requests are intentionally unaffected.
              if (navigationAction.isForMainFrame && !_isSelectedEmbedHost(uri.host)) {
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },
          ),
          if (_loading) const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
        ],
      ),
    );
  }
}
