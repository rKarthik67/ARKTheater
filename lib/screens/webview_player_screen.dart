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
/// This cannot guarantee zero ads the way native playback does, but it uses
/// the same compatible layers on every supported OS: narrow third-party ad
/// network rules, popup blocking, and tap-triggered redirect protection.
/// The request rules intentionally exclude broad patterns because those can
/// block a provider bootstrap script and leave the player blank.
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
  bool _canGoBackInBrowser = false;
  bool _playerPageReady = false;
  final Set<String> _playerHosts = <String>{};

  static final List<ContentBlocker> _contentBlockers = [
    for (final filter in embedSafeAdUrlFilters)
      ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: filter),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
      ),
  ];

  EmbedProvider get _provider => embedProviders[_providerIndex];

  String get _url =>
      _provider.urlFor(widget.type, widget.tmdbId, season: widget.season, episode: widget.episode);

  @override
  void initState() {
    super.initState();
    _providerIndex = widget.initialProviderIndex.clamp(0, embedProviders.length - 1);
    _playerHosts.add(WebUri(_url).host.toLowerCase());
  }

  void _switchProvider(int index) {
    if (index == _providerIndex) return;
    setState(() {
      _providerIndex = index;
      _loading = true;
      _canGoBackInBrowser = false;
      _playerPageReady = false;
      _playerHosts
        ..clear()
        ..add(WebUri(_url).host.toLowerCase());
    });
    _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(_url)));
  }

  Future<void> _updateBrowserHistory(InAppWebViewController controller) async {
    final canGoBack = await controller.canGoBack();
    if (mounted && canGoBack != _canGoBackInBrowser) {
      setState(() => _canGoBackInBrowser = canGoBack);
    }
  }

  Future<void> _returnToPlayer() async {
    final controller = _controller;
    if (controller == null) return;
    if (await controller.canGoBack()) {
      await controller.goBack();
    } else {
      // Many ad redirects use location.replace(), which intentionally
      // removes the player from WKWebView history. In that case a regular
      // browser Back action cannot work, so reopen the selected provider's
      // original embed page instead.
      setState(() => _loading = true);
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(_url)));
    }
    await _updateBrowserHistory(controller);
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
          IconButton(
            icon: const Icon(Icons.reply_outlined),
            tooltip: _canGoBackInBrowser ? 'Browser back' : 'Return to player',
            onPressed: _returnToPlayer,
          ),
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
            ),
            onWebViewCreated: (controller) {
              _controller = controller;
              _updateBrowserHistory(controller);
            },
            onLoadStart: (controller, url) {
              if (mounted) setState(() => _loading = true);
              _updateBrowserHistory(controller);
            },
            onLoadStop: (controller, url) async {
              if (url != null && !isAdOrTrackerHost(url.host)) {
                _playerHosts.add(url.host.toLowerCase());
              }
              // The first completed page load is the provider's normal
              // bootstrap. After it, an unknown top-level host is an ad
              // takeover rather than a required embed handoff.
              _playerPageReady = true;
              if (mounted) setState(() => _loading = false);
              await _updateBrowserHistory(controller);
            },
            // Extra safety net on top of supportMultipleWindows: false -
            // some platforms still route certain popups through here.
            // Returning false tells the plugin not to create a window for
            // it at all.
            onCreateWindow: (controller, createWindowAction) async => false,
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final uri = navigationAction.request.url;
              if (uri == null || isAdOrTrackerHost(uri.host)) {
                return NavigationActionPolicy.CANCEL;
              }

              // Allow the provider's automatic startup/auth redirects; iPad
              // embeds often need them. Once the player page is established,
              // reject any top-level jump to an untrusted host. iOS reports
              // hasGesture as null for many ad navigations, so this cannot
              // depend on that field.
              if (navigationAction.isForMainFrame &&
                  _playerPageReady &&
                  !_playerHosts.contains(uri.host.toLowerCase())) {
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
