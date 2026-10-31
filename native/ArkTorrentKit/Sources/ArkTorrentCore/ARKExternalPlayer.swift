import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Hands a resolved torrent stream URL off to the viewer's own installed
/// VLC app instead of the in-app player - the same "Play in VLC" choice
/// Android offers via an Intent (see TorrentStreamService.playInExternalVlc),
/// here via each platform's own hand-off mechanism since neither iOS nor
/// macOS has an Android-style Intent to resolve against.
public enum ARKExternalPlayer {
  public enum PlaybackError: Error, Equatable {
    case notInstalled
    case invalidURL
  }

  /// Always calls `completion` on the main queue.
  public static func playInVlc(urlString: String, completion: @escaping (Error?) -> Void) {
    #if os(iOS)
    guard URL(string: urlString) != nil, let vlcURL = URL(string: "vlc://\(urlString)") else {
      completion(PlaybackError.invalidURL)
      return
    }
    DispatchQueue.main.async {
      guard UIApplication.shared.canOpenURL(vlcURL) else {
        completion(PlaybackError.notInstalled)
        return
      }
      UIApplication.shared.open(vlcURL, options: [:]) { success in
        completion(success ? nil : PlaybackError.notInstalled)
      }
    }
    #elseif os(macOS)
    guard let streamURL = URL(string: urlString) else {
      completion(PlaybackError.invalidURL)
      return
    }
    DispatchQueue.main.async {
      guard
        let vlcAppURL = NSWorkspace.shared.urlForApplication(
          withBundleIdentifier: "org.videolan.vlc")
      else {
        completion(PlaybackError.notInstalled)
        return
      }
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.arguments = [urlString]
      NSWorkspace.shared.open(
        [streamURL], withApplicationAt: vlcAppURL, configuration: configuration
      ) { _, error in
        DispatchQueue.main.async { completion(error) }
      }
    }
    #endif
  }
}
