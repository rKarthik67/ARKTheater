import ArkTorrentCore
import CArkTorrent
import Foundation

#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif

/// Wires 'ark_theater/torrent' (MethodChannel) + 'ark_theater/torrent_status'
/// (EventChannel) to ARKTorrentEngine/TorrentHttpServer - the macOS/iOS
/// counterpart to the Android bridge's MainActivity.kt torrent handlers.
/// Method names and argument/result shapes match exactly, so
/// lib/services/torrent_stream_service.dart needs no Dart-side changes.
public enum ArkTorrentChannel {
  private static let methodChannelName = "ark_theater/torrent"
  private static let eventChannelName = "ark_theater/torrent_status"

  /// Mirrors MainActivity.kt's single-thread torrentExecutor: every torrent
  /// call (including the blocking startMagnet) runs serially off the
  /// platform thread.
  private static let queue = DispatchQueue(label: "ark.torrent.channel", qos: .userInitiated)

  private static var statusSink: FlutterEventSink?

  private static let cacheDirectory: String = {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.path
  }()

  private static let downloadsDirectory: String = {
    let base = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    let dir = base.appendingPathComponent("downloads", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.path
  }()

  public static func register(messenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
    methodChannel.setMethodCallHandler { call, result in
      handle(call, result: result)
    }

    let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
    eventChannel.setStreamHandler(StatusStreamHandler())
  }

  private static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "warmUp":
      queue.async {
        ARKTorrentEngine.shared().warmUp(cacheDirectory: cacheDirectory)
        DispatchQueue.main.async { result(nil) }
      }

    case "queueDownload":
      guard let magnet = stringArg(call, "magnet"), !magnet.isEmpty else {
        result(FlutterError(code: "invalid_magnet", message: "Missing magnet URI.", details: nil))
        return
      }
      queue.async {
        do {
          try ARKTorrentEngine.shared().queueDownload(
            magnet: magnet, downloadsDirectory: downloadsDirectory)
          DispatchQueue.main.async { result(nil) }
        } catch {
          DispatchQueue.main.async {
            result(
              FlutterError(
                code: "torrent_download_failed", message: error.localizedDescription,
                details: nil))
          }
        }
      }

    case "clearCache":
      queue.async {
        TorrentHttpServer.shared.stop()
        ARKTorrentEngine.shared().clearCache(
          cacheDirectory: cacheDirectory, downloadsDirectory: downloadsDirectory)
        DispatchQueue.main.async { result(nil) }
      }

    case "startMagnet":
      guard let magnet = stringArg(call, "magnet"), !magnet.isEmpty else {
        result(FlutterError(code: "invalid_magnet", message: "Missing magnet URI.", details: nil))
        return
      }
      let fileIndex = (call.arguments as? [String: Any])?["fileIndex"] as? NSNumber
      queue.async {
        startMagnet(magnet: magnet, fileIndex: fileIndex, result: result)
      }

    case "playExternalVlc":
      guard let url = stringArg(call, "url"), !url.isEmpty else {
        result(
          FlutterError(code: "invalid_stream", message: "Missing local torrent stream.", details: nil))
        return
      }
      ARKExternalPlayer.playInVlc(urlString: url) { error in
        if error == nil {
          result(nil)
        } else if case ARKExternalPlayer.PlaybackError.notInstalled = error! {
          result(
            FlutterError(
              code: "vlc_not_installed", message: "Install the VLC app to use this option.",
              details: nil))
        } else {
          result(
            FlutterError(
              code: "vlc_launch_failed", message: "\(error!.localizedDescription)", details: nil))
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func startMagnet(
    magnet: String, fileIndex: NSNumber?, result: @escaping FlutterResult
  ) {
    do {
      let started = try ARKTorrentEngine.shared().startMagnet(
        magnet,
        preferredFileIndex: fileIndex,
        cacheDirectory: cacheDirectory,
        statusHandler: { status in
          DispatchQueue.main.async { statusSink?(status) }
        })

      guard
        let streamUrl = TorrentHttpServer.shared.start(
          filePath: started.filePath,
          totalBytes: started.totalBytes,
          registerReader: { offset in ARKTorrentEngine.shared().registerReader(offset: offset) },
          availableUpTo: { from in ARKTorrentEngine.shared().availableContiguousBytes(from: from) }
        )
      else {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "torrent_start_failed", message: "Could not start the local stream server.",
              details: nil))
        }
        return
      }

      DispatchQueue.main.async {
        result([
          "fileUri": streamUrl,
          "fileName": started.fileName,
          "downloadedBytes": started.downloadedBytes,
          "totalBytes": started.totalBytes,
        ])
      }
    } catch {
      DispatchQueue.main.async {
        result(
          FlutterError(
            code: "torrent_start_failed", message: error.localizedDescription, details: nil))
      }
    }
  }

  private static func stringArg(_ call: FlutterMethodCall, _ key: String) -> String? {
    (call.arguments as? [String: Any])?[key] as? String
  }

  private final class StatusStreamHandler: NSObject, FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
      -> FlutterError?
    {
      statusSink = events
      return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
      statusSink = nil
      return nil
    }
  }
}
