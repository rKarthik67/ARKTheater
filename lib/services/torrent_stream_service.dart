import 'package:flutter/services.dart';

/// Android bridge for a user-supplied, legal magnet URI. Discovery is not a
/// responsibility of the app: the native side receives only the exact magnet
/// the viewer supplied and returns a local, progressively downloaded file.
class TorrentStreamService {
  TorrentStreamService._();

  static const _channel = MethodChannel('ark_theater/torrent');
  static const _statusChannel = EventChannel('ark_theater/torrent_status');

  static Stream<TorrentStreamStatus> get statuses => _statusChannel
      .receiveBroadcastStream()
      .where((value) => value is Map)
      .map((value) =>
          TorrentStreamStatus.fromMap(Map<String, dynamic>.from(value)));

  /// [fileIndex] is which file within a multi-file torrent is the actual
  /// requested title/episode (see TorrentSource.fileIndex) - `null` lets
  /// the native side fall back to its own "largest video file" guess,
  /// which is the only option for single-file releases anyway.
  static Future<TorrentStreamResult> startMagnet(
    String magnet, {
    int? fileIndex,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'startMagnet',
      {'magnet': magnet, if (fileIndex != null) 'fileIndex': fileIndex},
    );
    final uri = result?['fileUri'] as String?;
    if (uri == null || uri.isEmpty) {
      throw PlatformException(
        code: 'torrent_start_failed',
        message: 'Torrent source did not return a playable file.',
      );
    }
    return TorrentStreamResult(
      fileUri: uri,
      fileName: result?['fileName'] as String? ?? 'Torrent video',
      downloadedBytes: (result?['downloadedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (result?['totalBytes'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<void> queueDownload(String magnet) =>
      _channel.invokeMethod<void>('queueDownload', {'magnet': magnet});

  /// Hands the resolved local stream URL to the viewer's own installed VLC
  /// app (via Intent) instead of the default in-app ExoPlayer-based player
  /// (see MobilePlayerScreen) - VLC bundles its own software decoders/
  /// demuxer, so it isn't subject to ExoPlayer-specific extractor behavior
  /// (e.g. MatroskaExtractor's upfront end-of-file Cues read) or the
  /// platform MediaCodec's codec licensing gaps. Throws if VLC isn't
  /// installed.
  static Future<void> playInExternalVlc({
    required String url,
    required String title,
  }) =>
      _channel.invokeMethod<void>('playExternalVlc', {'url': url, 'title': title});

  /// Starts the libtorrent session (DHT bootstrap etc.) ahead of time, the
  /// moment the torrent source picker opens - rather than only from the
  /// instant the viewer taps a magnet - so that cold-start cost overlaps
  /// with the catalogue lookup instead of adding to it. Best-effort: a
  /// failure here just means the first real play pays the normal cold-start
  /// cost, so errors are swallowed rather than surfaced.
  static Future<void> warmUp() =>
      _channel.invokeMethod<void>('warmUp').catchError((_) {});

  /// Settings > Data & Storage > Clear Torrent Cache: stops any in-flight
  /// stream and wipes both the streaming cache and queued-download files.
  static Future<void> clearCache() =>
      _channel.invokeMethod<void>('clearCache');
}

class TorrentStreamStatus {
  const TorrentStreamStatus({
    required this.state,
    required this.peers,
    required this.downloadRate,
    required this.progress,
  });

  factory TorrentStreamStatus.fromMap(Map<String, dynamic> map) =>
      TorrentStreamStatus(
        state: map['state']?.toString() ?? 'Finding peers',
        peers: (map['peers'] as num?)?.toInt() ?? 0,
        downloadRate: (map['downloadRate'] as num?)?.toInt() ?? 0,
        progress: (map['progress'] as num?)?.toDouble() ?? 0,
      );

  final String state;
  final int peers;
  final int downloadRate;
  final double progress;

  String get label {
    final kib = downloadRate / 1024;
    final rate = kib >= 1024
        ? '${(kib / 1024).toStringAsFixed(1)} MB/s'
        : '${kib.toStringAsFixed(0)} kB/s';
    return '$state · $rate · $peers peers · ${(progress * 100).toStringAsFixed(0)}%';
  }
}

class TorrentStreamResult {
  const TorrentStreamResult({
    required this.fileUri,
    required this.fileName,
    required this.downloadedBytes,
    required this.totalBytes,
  });

  final String fileUri;
  final String fileName;
  final int downloadedBytes;
  final int totalBytes;
}
