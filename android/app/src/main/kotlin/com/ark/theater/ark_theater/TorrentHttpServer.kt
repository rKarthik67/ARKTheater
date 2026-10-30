package com.ark.theater.ark_theater

import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.io.RandomAccessFile
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors

/**
 * Presents the selected torrent file as a range-capable localhost HTTP stream.
 * ExoPlayer cannot reliably play a growing file:// source: it treats the first
 * unwritten region as end-of-file. This server instead blocks each byte range
 * until libtorrent reports that range as downloaded, which is the hand-off a
 * streaming player expects.
 */
object TorrentHttpServer {
    private val executor = Executors.newCachedThreadPool()
    private var socket: ServerSocket? = null

    /**
     * [availableUpTo] answers "given a request starting at this byte
     * offset, up to which absolute byte is it contiguously downloaded" -
     * it takes the request's own start, not just byte 0. A single
     * zero-argument "available from the start of the file" check (the
     * previous shape of this callback) works fine for plain front-to-back
     * sequential playback, but hangs forever on any read that doesn't
     * begin at byte 0 - a seek, or (as turned out to be the actual cause
     * of "TV shows never play") ExoPlayer's MatroskaExtractor opening a
     * range near the END of the file first to read the Cues/seek index:
     * that region can be fully downloaded already while the *front* of a
     * multi-GB file isn't, so "contiguous from byte 0" never reaches the
     * requested position no matter how long you wait.
     */
    @Synchronized
    fun start(file: File, totalBytes: Long, availableUpTo: (Long) -> Long): String {
        socket?.close()
        val server = ServerSocket(0, 16, InetAddress.getByName("127.0.0.1"))
        socket = server
        executor.execute {
            while (!server.isClosed) {
                try {
                    // accept() can intermittently throw EAGAIN on BlueStacks.
                    // It must execute inside this guarded loop; letting it run
                    // in an executor lambda makes the uncaught exception crash
                    // the complete Android process.
                    val client = server.accept()
                    executor.execute {
                        try {
                            serve(client, file, totalBytes, availableUpTo)
                        } catch (_: Throwable) {
                            try { client.close() } catch (_: Throwable) { }
                        }
                    }
                } catch (_: Throwable) {
                    if (!server.isClosed) Thread.sleep(100)
                }
            }
        }
        return "http://127.0.0.1:${server.localPort}/stream"
    }

    private fun serve(
        socket: Socket,
        file: File,
        totalBytes: Long,
        availableUpTo: (Long) -> Long,
    ) {
        socket.use { client ->
            val reader = BufferedReader(InputStreamReader(client.getInputStream()))
            var range: String? = null
            while (true) {
                val line = reader.readLine() ?: return
                if (line.isEmpty()) break
                if (line.startsWith("Range:", ignoreCase = true)) {
                    range = line.substringAfter(':').trim()
                }
            }
            val bounds = parseRange(range, totalBytes) ?: return
            val (start, end) = bounds
            // Retarget the scheduler the instant a range is parsed, before
            // blocking on any byte - a seek (or the player simply reading
            // ahead) must not wait for the next tick to start rushing the
            // pieces it actually needs.
            TorrentStreamManager.registerReader(start)
            val output = client.getOutputStream()
            val header = buildString {
                append("HTTP/1.1 206 Partial Content\r\n")
                append("Content-Type: video/mp4\r\n")
                append("Accept-Ranges: bytes\r\n")
                append("Content-Range: bytes $start-$end/$totalBytes\r\n")
                append("Content-Length: ${end - start + 1}\r\n")
                append("Connection: close\r\n\r\n")
            }
            output.write(header.toByteArray())
            output.flush()

            RandomAccessFile(file, "r").use { input ->
                var position = start
                var lastRegistered = start
                val buffer = ByteArray(64 * 1024)
                while (position <= end) {
                    // registerReader was only ever called once, with the
                    // request's original start - for one long-lived
                    // connection streaming forward byte by byte (the normal
                    // case; a single "bytes=X-" request can cover the rest
                    // of the whole file), the scheduler's rush/readahead
                    // window stayed pinned at that original point forever,
                    // never following where this connection actually got
                    // to. Once it read past that initial window, newly
                    // needed pieces had nothing keeping them prioritized.
                    // Re-registering as the cursor moves keeps the window
                    // centered on where playback truly is.
                    if (position - lastRegistered >= 1024 * 1024) {
                        lastRegistered = position
                        TorrentStreamManager.registerReader(position)
                    }
                    val available = try { availableUpTo(position).coerceAtLeast(0L) } catch (_: Exception) { 0L }
                    if (position >= available) {
                        Thread.sleep(120)
                        continue
                    }
                    val count = minOf(buffer.size.toLong(), end - position + 1, available - position).toInt()
                    input.seek(position)
                    val read = input.read(buffer, 0, count)
                    if (read <= 0) {
                        Thread.sleep(120)
                        continue
                    }
                    output.write(buffer, 0, read)
                    output.flush()
                    position += read
                }
            }
        }
    }

    private fun parseRange(value: String?, total: Long): Pair<Long, Long>? {
        if (total <= 0) return null
        val raw = value?.removePrefix("bytes=")?.split('-', limit = 2)
        val start = raw?.getOrNull(0)?.toLongOrNull() ?: 0L
        val requestedEnd = raw?.getOrNull(1)?.toLongOrNull() ?: (total - 1)
        if (start !in 0 until total) return null
        return start to requestedEnd.coerceIn(start, total - 1)
    }
}
