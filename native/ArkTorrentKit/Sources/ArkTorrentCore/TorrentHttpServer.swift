import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Presents the selected torrent file as a range-capable localhost HTTP
/// stream - a direct port of the Android bridge's TorrentHttpServer.kt onto
/// POSIX sockets (mirrors its blocking-accept/blocking-read model instead of
/// Network.framework's callback-based API, since the player-facing behavior
/// here - block each byte range until libtorrent reports it downloaded - is
/// inherently a blocking-I/O pattern).
public final class TorrentHttpServer {
  public static let shared = TorrentHttpServer()

  private let lock = NSLock()
  private var listenSocket: Int32 = -1
  private let acceptQueue = DispatchQueue(label: "ark.torrent.http.accept")

  private init() {}

  /// Starts (replacing any previous instance) the server over `filePath`,
  /// returning "http://127.0.0.1:PORT/stream" once bound, or nil on
  /// failure. `registerReader`/`availableUpTo` are the same reader-position
  /// hooks TorrentHttpServer.kt threads through to TorrentStreamManager.
  public func start(
    filePath: String,
    totalBytes: Int64,
    registerReader: @escaping (Int64) -> Void,
    availableUpTo: @escaping (Int64) -> Int64
  ) -> String? {
    lock.lock()
    defer { lock.unlock() }
    stopLocked()

    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    var reuse: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

    var addr = sockaddr_in()
    addr.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = 0  // ask the OS for a free port
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")

    let bindResult = withUnsafePointer(to: &addr) { pointer -> Int32 in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bindResult == 0, listen(fd, 16) == 0 else {
      close(fd)
      return nil
    }

    var boundAddr = sockaddr_in()
    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    let gotName = withUnsafeMutablePointer(to: &boundAddr) { pointer -> Int32 in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        getsockname(fd, $0, &len)
      }
    }
    guard gotName == 0 else {
      close(fd)
      return nil
    }
    let port = UInt16(bigEndian: boundAddr.sin_port)

    listenSocket = fd
    acceptQueue.async { [weak self] in
      self?.acceptLoop(
        fd: fd, filePath: filePath, totalBytes: totalBytes,
        registerReader: registerReader, availableUpTo: availableUpTo)
    }
    return "http://127.0.0.1:\(port)/stream"
  }

  public func stop() {
    lock.lock()
    defer { lock.unlock() }
    stopLocked()
  }

  private func stopLocked() {
    if listenSocket >= 0 {
      close(listenSocket)
      listenSocket = -1
    }
  }

  private func acceptLoop(
    fd: Int32, filePath: String, totalBytes: Int64,
    registerReader: @escaping (Int64) -> Void,
    availableUpTo: @escaping (Int64) -> Int64
  ) {
    while true {
      let client = accept(fd, nil, nil)
      if client < 0 {
        // Either this listener was replaced/stopped, or a transient accept
        // failure - only the former should end the loop.
        lock.lock()
        let stillActive = listenSocket == fd
        lock.unlock()
        if !stillActive { return }
        usleep(100_000)
        continue
      }
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        self?.serve(
          client: client, filePath: filePath, totalBytes: totalBytes,
          registerReader: registerReader, availableUpTo: availableUpTo)
      }
    }
  }

  private func serve(
    client: Int32, filePath: String, totalBytes: Int64,
    registerReader: @escaping (Int64) -> Void,
    availableUpTo: @escaping (Int64) -> Int64
  ) {
    defer { close(client) }
    guard let rangeValue = readRangeHeader(client: client),
      let bounds = parseRange(rangeValue, total: totalBytes)
    else { return }
    let (start, end) = bounds

    // Retarget the scheduler before blocking on any byte - a seek must not
    // wait for the scheduler's next tick to start rushing the pieces it
    // actually needs.
    registerReader(start)

    let header =
      "HTTP/1.1 206 Partial Content\r\n" + "Content-Type: video/mp4\r\n"
      + "Accept-Ranges: bytes\r\n" + "Content-Range: bytes \(start)-\(end)/\(totalBytes)\r\n"
      + "Content-Length: \(end - start + 1)\r\n" + "Connection: close\r\n\r\n"
    guard writeAll(client, Array(header.utf8)) else { return }

    guard let handle = FileHandle(forReadingAtPath: filePath) else { return }
    defer { handle.closeFile() }

    var position = start
    var lastRegistered = start
    let chunkSize = 64 * 1024

    while position <= end {
      // Re-registering as the cursor moves keeps the scheduler's
      // rush/readahead window centered on where playback truly is, not
      // pinned at the request's original start forever.
      if position - lastRegistered >= 1024 * 1024 {
        lastRegistered = position
        registerReader(position)
      }
      let available = max(0, availableUpTo(position))
      if position >= available {
        usleep(120_000)
        continue
      }
      let toRead = Int(min(Int64(chunkSize), end - position + 1, available - position))
      handle.seek(toFileOffset: UInt64(position))
      let data = handle.readData(ofLength: toRead)
      if data.isEmpty {
        usleep(120_000)
        continue
      }
      guard writeAll(client, [UInt8](data)) else { return }
      position += Int64(data.count)
    }
  }

  private func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
    var offset = 0
    return bytes.withUnsafeBufferPointer { buffer -> Bool in
      while offset < buffer.count {
        let n = write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
        if n <= 0 { return false }
        offset += n
      }
      return true
    }
  }

  private func readRangeHeader(client: Int32) -> String? {
    var range: String?
    var lineBuffer: [UInt8] = []
    var byte: UInt8 = 0
    while true {
      let n = read(client, &byte, 1)
      if n <= 0 { return range }
      if byte == 0x0A {  // \n
        let line = String(decoding: lineBuffer, as: UTF8.self)
          .trimmingCharacters(in: .whitespaces)
        lineBuffer.removeAll()
        if line.isEmpty { return range }
        if line.lowercased().hasPrefix("range:") {
          range = String(line.dropFirst("range:".count)).trimmingCharacters(in: .whitespaces)
        }
      } else if byte != 0x0D {
        lineBuffer.append(byte)
      }
    }
  }

  private func parseRange(_ value: String?, total: Int64) -> (Int64, Int64)? {
    guard total > 0 else { return nil }
    let raw = (value ?? "").replacingOccurrences(of: "bytes=", with: "")
    let parts = raw.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    let start = parts.first.flatMap { Int64($0) } ?? 0
    let requestedEnd: Int64? =
      (parts.count > 1 && !parts[1].isEmpty) ? Int64(parts[1]) : nil
    guard start >= 0, start < total else { return nil }
    let end = min(max(requestedEnd ?? (total - 1), start), total - 1)
    return (start, end)
  }
}
