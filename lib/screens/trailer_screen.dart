import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Plays a YouTube trailer inline - reuses the flutter_inappwebview
/// dependency already pulled in for WebViewPlayerScreen instead of adding a
/// dedicated YouTube-player package just for this.
class TrailerScreen extends StatelessWidget {
  const TrailerScreen({super.key, required this.title, required this.youtubeKey});

  final String title;
  final String youtubeKey;

  @override
  Widget build(BuildContext context) {
    final embedUrl = 'https://www.youtube.com/embed/$youtubeKey?autoplay=1&playsinline=1';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('$title · Trailer', overflow: TextOverflow.ellipsis),
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(embedUrl)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          allowsInlineMediaPlayback: true,
        ),
      ),
    );
  }
}
