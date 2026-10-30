package com.ark.theater.ark_theater

import android.app.ActivityManager
import android.content.Context
import android.util.Log
import org.libtorrent4j.Priority
import org.libtorrent4j.SessionManager
import org.libtorrent4j.Sha1Hash
import org.libtorrent4j.SettingsPack
import org.libtorrent4j.TorrentHandle
import org.libtorrent4j.TorrentInfo
import org.libtorrent4j.swig.settings_pack
import org.libtorrent4j.swig.torrent_flags_t
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * Small Android-only bridge around libtorrent. It intentionally accepts a
 * magnet supplied by the user; discovery/catalogue lookup stays out of the
 * app. Once enough of the selected video has arrived, the player can open
 * the localhost HTTP stream while libtorrent continues downloading, with
 * piece scheduling driven by the player's actual read position (see
 * [Scheduler]) rather than plain sequential order.
 */
object TorrentStreamManager {
    // Was 12MB. A real player only needs to parse the container header and
    // has a few seconds of video queued up before it can start - 12MB is
    // 15-25s of video at typical bitrates, i.e. far more prefix than
    // playback actually needs before the first frame, which is exactly the
    // kind of avoidable startup latency Watchly's bitrate-aware pre-roll
    // (as little as ~3s of video, see its rolling-cache-architecture.md)
    // avoids. 4MB covers a few seconds at most torrent-release bitrates
    // without the engine needing to estimate the actual bitrate.
    private const val startupBytes = 4L * 1024L * 1024L
    private const val timeoutMs = 120_000L
    private val videoExtensions = setOf("mp4", "mkv", "webm", "avi", "mov", "m4v", "ts")

    private var session: SessionManager? = null
    private var scheduler: Scheduler? = null

    /**
     * Mirrors Watchly's own session tuning (its TorrentStream.kt) - plain
     * default libtorrent settings connect to peers cautiously and give a
     * stalled request a long time before retrying elsewhere, which reads
     * as "stuck forever" well before ExoPlayer's own HTTP timeout even
     * fires. Low peer-connect/request timeouts mean a dead peer or a
     * stalled request is abandoned and retried in seconds, not tens of
     * seconds; the connect-speed/boost and deep request queue make the
     * swarm ramp up fast instead of trickling in peer-by-peer.
     */
    private fun tunedSettings(context: Context): SettingsPack {
        val activityManager =
            context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager?.getMemoryInfo(memoryInfo)
        val tightMemory = memoryInfo.totalMem in 1..(3L * 1024 * 1024 * 1024)
        val peers = if (tightMemory) 80 else 200

        return SettingsPack()
            .connectionsLimit(peers)
            .activeDhtLimit(88)
            .downloadRateLimit(0)
            .uploadRateLimit(0)
            .setInteger(settings_pack.int_types.torrent_connect_boost.swigValue(), peers)
            .setInteger(settings_pack.int_types.connection_speed.swigValue(), peers)
            .setInteger(settings_pack.int_types.peer_connect_timeout.swigValue(), 5)
            .setInteger(settings_pack.int_types.whole_pieces_threshold.swigValue(), 10)
            .setInteger(settings_pack.int_types.request_timeout.swigValue(), 6)
            .setBoolean(settings_pack.bool_types.strict_end_game_mode.swigValue(), false)
            .setInteger(settings_pack.int_types.max_out_request_queue.swigValue(), 1500)
            .setBoolean(settings_pack.bool_types.close_redundant_connections.swigValue(), false)
    }

    @Synchronized
    private fun ensureSession(context: Context): SessionManager =
        session ?: SessionManager().also {
            it.start()
            it.applySettings(tunedSettings(context))
            session = it
        }

    /** Called the instant the torrent source picker opens (see
     * TorrentSourceList.initState), well before the viewer has chosen a
     * magnet. Starting the session and letting its DHT routing table begin
     * populating in parallel with the catalogue lookup - instead of only
     * from the moment "play" is tapped - removes a cold-start delay that
     * otherwise lands on every first torrent play of an app session. */
    @Synchronized
    fun warmUp(context: Context) {
        ensureSession(context)
    }

    @Synchronized
    fun queueDownload(context: Context, magnet: String) {
        require(magnet.startsWith("magnet:?", ignoreCase = true)) { "Enter a valid magnet URI." }
        val manager = ensureSession(context)
        val saveDir = File(context.getExternalFilesDir(null), "downloads").apply { mkdirs() }
        manager.download(magnet, saveDir, torrent_flags_t())
    }

    /** Settings > Data & Storage > Clear Torrent Cache. Stops any in-flight
     * stream and wipes both the streaming cache and the queued-download
     * directory. */
    @Synchronized
    fun clearCache(context: Context) {
        scheduler?.stop()
        scheduler = null
        session?.stop()
        session = null
        File(context.cacheDir, "torrent-streams").deleteRecursively()
        File(context.getExternalFilesDir(null), "downloads").deleteRecursively()
    }

    /**
     * Called by [TorrentHttpServer] the instant it parses a new Range
     * request, so a seek (or the player simply reading ahead) retargets
     * piece priorities immediately instead of waiting for the swarm to
     * reach that offset in download order.
     */
    fun registerReader(offsetInFile: Long) {
        scheduler?.retarget(offsetInFile)
    }

    /**
     * [preferredFileIndex], when supplied, is which file within a
     * multi-file torrent the catalogue already identified as the requested
     * title/episode (Torrentio's season-pack hint, threaded through from
     * TorrentSource.fileIndex). Season-pack releases are the norm for TV
     * rather than the exception, and without this hint the only option is
     * [largestVideoIndex]'s "biggest video file in the torrent" guess -
     * which is very often the wrong episode, one with no particular reason
     * to be well-seeded for the viewer's actual swarm. An invalid or
     * non-video index is ignored and falls back to that guess, same as
     * when no hint is given at all (single-file releases, EZTV results).
     */
    @Synchronized
    fun startMagnet(
        context: Context,
        magnet: String,
        preferredFileIndex: Int?,
        onStatus: (Map<String, Any>) -> Unit,
    ): Map<String, Any> {
        require(magnet.startsWith("magnet:?", ignoreCase = true)) {
            "Enter a valid magnet URI."
        }

        scheduler?.stop()
        scheduler = null

        val manager = ensureSession(context)
        val saveDir = File(context.cacheDir, "torrent-streams").apply { mkdirs() }
        manager.download(magnet, saveDir, torrent_flags_t())

        val deadline = System.currentTimeMillis() + timeoutMs
        var handle: TorrentHandle? = null
        var selectedPath: String? = null
        var selectedIndex = -1
        var startedScheduler: Scheduler? = null

        while (System.currentTimeMillis() < deadline) {
            // The manager exposes its active handles through the session only
            // after libtorrent has accepted the magnet. Resolve by matching
            // the torrent name/path after metadata is available.
            val candidate = activeHandle(manager, magnet)
            if (candidate != null) {
                handle = candidate
                val status = candidate.status()
                onStatus(
                    mapOf(
                        "state" to if (status.hasMetadata()) "Buffering" else "Finding peers",
                        "peers" to status.numPeers(),
                        "downloadRate" to status.downloadRate(),
                        "progress" to status.progress(),
                    ),
                )
                val info = candidate.torrentFile()
                if (info != null) {
                    if (selectedIndex < 0) {
                        selectedIndex = preferredFileIndex
                            ?.takeIf { it in 0 until info.numFiles() }
                            ?.takeIf {
                                info.files().fileName(it).substringAfterLast('.', "")
                                    .lowercase() in videoExtensions
                            }
                            ?: largestVideoIndex(info, saveDir)
                        if (selectedIndex >= 0) {
                            selectedPath = info.files().filePath(selectedIndex, saveDir.absolutePath)
                            Log.i(
                                "TorrentStream",
                                "selected file $selectedIndex/${info.numFiles()} " +
                                    "'${info.files().fileName(selectedIndex)}' " +
                                    "(${info.files().fileSize(selectedIndex) / 1_000_000}MB), " +
                                    "preferred=$preferredFileIndex",
                            )
                            deprioritizeOtherFiles(candidate, info, selectedIndex)
                            startedScheduler = Scheduler(candidate, info, selectedIndex).also {
                                it.start()
                                scheduler = it
                            }
                        }
                    }
                    if (selectedIndex >= 0) {
                        val total = info.files().fileSize(selectedIndex)
                        val contiguous = contiguousPrefix(candidate, info, selectedIndex, total)
                        if (contiguous >= minOf(startupBytes, total)) {
                            val file = File(selectedPath!!)
                            val streamUrl = TorrentHttpServer.start(file, total) { fromByte ->
                                contiguousAvailableFrom(candidate, info, selectedIndex, total, fromByte)
                            }
                            return mapOf(
                                "fileUri" to streamUrl,
                                "fileName" to info.files().fileName(selectedIndex),
                                "downloadedBytes" to contiguous,
                                "totalBytes" to total,
                            )
                        }
                    }
                }
            } else {
                onStatus(mapOf("state" to "Connecting to peers", "peers" to 0, "downloadRate" to 0, "progress" to 0f))
            }
            Thread.sleep(500)
        }

        startedScheduler?.stop()
        if (handle == null) {
            throw IllegalStateException("Could not add this torrent. Check the magnet URI and try again.")
        }
        if (selectedIndex < 0) {
            throw IllegalStateException("No supported video file was found in this torrent.")
        }
        throw IllegalStateException("No playable data arrived in two minutes. Check seed availability.")
    }

    /** Multi-file releases (samples, extras, subtitle packs) otherwise split
     * the swarm's bandwidth across files the viewer never asked for. */
    private fun deprioritizeOtherFiles(handle: TorrentHandle, info: TorrentInfo, selectedIndex: Int) {
        val priorities = Array(info.numFiles()) { index ->
            if (index == selectedIndex) Priority.DEFAULT else Priority.IGNORE
        }
        handle.prioritizeFiles(priorities)
    }

    // jlibtorrent's high-level SessionManager does not publish a torrent
    // collection. The info-hash is encoded in a standard btih magnet and is
    // used to retrieve its handle from the running session.
    private fun activeHandle(manager: SessionManager, magnet: String): TorrentHandle? {
        val rawHash = Regex("[?&]xt=urn:btih:([^&]+)", RegexOption.IGNORE_CASE)
            .find(magnet)?.groupValues?.get(1) ?: return null
        val hash = when {
            rawHash.matches(Regex("[a-fA-F0-9]{40}")) -> rawHash
            rawHash.matches(Regex("[a-zA-Z2-7]{32}")) -> base32ToHex(rawHash)
            else -> return null
        }
        return manager.find(Sha1Hash.parseHex(hash))
    }

    private fun base32ToHex(value: String): String {
        val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var bits = 0
        var buffer = 0
        val output = StringBuilder(40)
        for (character in value.uppercase()) {
            buffer = (buffer shl 5) or alphabet.indexOf(character)
            bits += 5
            while (bits >= 8) {
                bits -= 8
                output.append("%02x".format((buffer shr bits) and 0xff))
            }
        }
        return output.toString()
    }

    private fun largestVideoIndex(
        info: TorrentInfo,
        saveDir: File,
    ): Int {
        var best = -1
        var bestSize = -1L
        for (index in 0 until info.numFiles()) {
            val extension = info.files().fileName(index).substringAfterLast('.', "").lowercase()
            if (extension in videoExtensions && info.files().fileSize(index) > bestSize) {
                best = index
                bestSize = info.files().fileSize(index)
            }
        }
        return best
    }

    private fun contiguousPrefix(
        handle: TorrentHandle,
        info: TorrentInfo,
        fileIndex: Int,
        fileSize: Long,
    ): Long {
        val storage = info.files()
        val fileStart = storage.fileOffset(fileIndex)
        val fileEnd = fileStart + fileSize
        val first = storage.pieceIndexAtFile(fileIndex)
        val last = storage.lastPieceIndexAtFile(fileIndex)
        var available = 0L
        for (piece in first..last) {
            if (!handle.havePiece(piece)) break
            val pieceStart = piece.toLong() * info.pieceLength()
            val pieceEnd = minOf(pieceStart + info.pieceSize(piece), fileEnd)
            available += (pieceEnd - maxOf(pieceStart, fileStart)).coerceAtLeast(0L)
        }
        return available.coerceAtMost(fileSize)
    }

    /**
     * Like [contiguousPrefix], but anchored at an arbitrary [fromByte]
     * instead of always byte 0 - used for every HTTP range request once
     * the stream is already playing (see [TorrentHttpServer]). A request
     * that doesn't start at byte 0 - a seek, or ExoPlayer's MatroskaExtractor
     * reading the MKV Cues element near the *end* of the file before normal
     * playback even starts - needs "is everything from here contiguous",
     * not "is everything from the very start of the file contiguous"; the
     * tail of a multi-GB file can easily be fully downloaded while the
     * front still has large gaps (reader-driven, non-sequential scheduling
     * means the two are unrelated), so checking from byte 0 would never
     * unblock that read no matter how long the server waited.
     */
    private fun contiguousAvailableFrom(
        handle: TorrentHandle,
        info: TorrentInfo,
        fileIndex: Int,
        fileSize: Long,
        fromByte: Long,
    ): Long {
        val storage = info.files()
        val fileStart = storage.fileOffset(fileIndex)
        val fileEnd = fileStart + fileSize
        val from = (fileStart + fromByte).coerceIn(fileStart, fileEnd)
        val startPiece = (from / info.pieceLength()).toInt().coerceIn(
            storage.pieceIndexAtFile(fileIndex),
            storage.lastPieceIndexAtFile(fileIndex),
        )
        val last = storage.lastPieceIndexAtFile(fileIndex)
        var boundary = from
        for (piece in startPiece..last) {
            if (!handle.havePiece(piece)) break
            val pieceStart = piece.toLong() * info.pieceLength()
            val pieceEnd = minOf(pieceStart + info.pieceSize(piece), fileEnd)
            if (pieceEnd <= boundary) continue
            boundary = pieceEnd
        }
        return (boundary - fileStart).coerceIn(fromByte, fileSize)
    }

    /**
     * Reader-position-driven piece scheduler, replacing plain sequential
     * download. Every tick it computes three zones relative to the single
     * active reader's byte offset within the selected file:
     *
     * - A small **rush window** immediately ahead gets `TOP_PRIORITY` plus
     *   an absolute deadline (nearest piece soonest), which is what
     *   actually unblocks [TorrentHttpServer]'s blocking read loop.
     * - A larger **readahead window** further ahead gets `DEFAULT`
     *   priority so the swarm keeps working past the rush zone.
     * - A small **rewind margin** behind the reader stays at `LOW`
     *   priority (cheap small rewinds without a fresh stall).
     * - Everything else in the file is `IGNORE`d.
     *
     * Sequential mode is deliberately not used: it hands the next piece to
     * whichever peer happens to be slowest, which is the actual mechanism
     * behind "plays a little, then buffers forever" once the fast prefix
     * window runs out.
     */
    private class Scheduler(
        private val handle: TorrentHandle,
        info: TorrentInfo,
        fileIndex: Int,
    ) {
        private companion object {
            const val tickMs = 500L
            const val rushBytes = 6L * 1024 * 1024
            const val readaheadBytes = 48L * 1024 * 1024
            const val rewindBytes = 12L * 1024 * 1024
            // MKV's seek index (Cues) commonly sits at the very end of the
            // file, not the front - ExoPlayer's MatroskaExtractor reads it
            // there before normal sequential playback even starts, which
            // works fine against a plain web server (seeking is free) but
            // is exactly backwards for a torrent: the tail is often the
            // least-downloaded part of the swarm. Reader-driven scheduling
            // alone only reacts to this *after* the extractor blocks on it
            // - keeping the tail at DEFAULT priority unconditionally, from
            // the first tick, means it's usually already there (or already
            // in flight) by the time it's actually needed. Mirrors
            // Watchly's own explicit tail-of-file priority window.
            const val tailBytes = 4L * 1024 * 1024
            // Was 15s. Watchly's own engine re-kicks a blocked piece after
            // 5s - a long threshold here is exactly why a stall reads as
            // "stuck forever": ExoPlayer's HTTP client times out reading
            // the local stream (~8-30s) before this watchdog would even
            // have fired once.
            const val stallMs = 5_000L
            // Below this, the fetch window narrows to just the rush zone
            // (see tick()) so the swarm isn't still spreading requests
            // across a wide readahead while the one piece actually blocking
            // playback can't get satisfied.
            const val starveMs = 5_000L
            // How often to nudge a stalled swarm (force a tracker/DHT
            // re-announce) rather than just waiting - mirrors Watchly's
            // SHAKE_INTERVAL_MS.
            const val shakeIntervalMs = 10_000L
        }

        private val fileStart = info.files().fileOffset(fileIndex)
        private val fileLength = info.files().fileSize(fileIndex)
        private val firstPiece = info.files().pieceIndexAtFile(fileIndex)
        private val lastPiece = info.files().lastPieceIndexAtFile(fileIndex)
        private val pieceLength = info.pieceLength().toLong()

        private val target = AtomicLong(0L)
        private val running = AtomicBoolean(true)
        private var lastTargetPiece = -1
        private var rushSince = 0L
        private var lastDataAt = System.currentTimeMillis()
        private var lastShakeAt = 0L
        private var lastLogAt = 0L
        private var thread: Thread? = null

        fun retarget(offsetInFile: Long) {
            target.set(offsetInFile.coerceIn(0L, (fileLength - 1).coerceAtLeast(0L)))
        }

        fun start() {
            thread = Thread {
                while (running.get()) {
                    try {
                        tick()
                    } catch (_: Throwable) {
                        // The torrent handle can go invalid mid-tick if the
                        // session is reset by a new startMagnet() call;
                        // stop() will already have been requested by then.
                    }
                    Thread.sleep(tickMs)
                }
            }.apply { isDaemon = true; start() }
        }

        fun stop() {
            running.set(false)
        }

        private fun tick() {
            val now = System.currentTimeMillis()
            val absoluteTarget = fileStart + target.get()
            val targetPiece = (absoluteTarget / pieceLength).toInt().coerceIn(firstPiece, lastPiece)
            val rushPieces = ((rushBytes + pieceLength - 1) / pieceLength).toInt().coerceAtLeast(1)
            val rewindPieces = ((rewindBytes + pieceLength - 1) / pieceLength).toInt()

            if (targetPiece != lastTargetPiece) {
                lastTargetPiece = targetPiece
                rushSince = now
            }

            val blocked = !handle.havePiece(targetPiece)
            // Starving: concentrate every request on the rush zone instead
            // of also spreading default-priority requests across the full
            // readahead while the one piece actually blocking playback
            // can't get satisfied - mirrors Watchly's width narrowing.
            val starving = blocked && now - rushSince > starveMs
            val readaheadPieces = if (starving) rushPieces else
                ((readaheadBytes + pieceLength - 1) / pieceLength).toInt().coerceAtLeast(rushPieces)

            val rushEnd = minOf(lastPiece, targetPiece + rushPieces)
            val readaheadEnd = minOf(lastPiece, targetPiece + readaheadPieces)
            val rewindStart = maxOf(firstPiece, targetPiece - rewindPieces)
            val tailPieces = ((tailBytes + pieceLength - 1) / pieceLength).toInt().coerceAtLeast(1)
            val tailStart = maxOf(firstPiece, lastPiece - tailPieces + 1)

            for (piece in firstPiece..lastPiece) {
                if (handle.havePiece(piece)) continue
                val inTail = piece in tailStart..lastPiece
                val priority = when {
                    piece in targetPiece..rushEnd -> Priority.TOP_PRIORITY
                    // Rushed, not just left at DEFAULT: proven in practice
                    // (see tick()'s doc comment) that some releases' Cues
                    // region is genuinely rare in the swarm - DEFAULT-only
                    // priority left it arriving too late once the extractor
                    // actually blocked on it. Deadline is well behind the
                    // live rush zone's so it never competes for bandwidth
                    // with whatever's actually in front of playback.
                    inTail -> Priority.TOP_PRIORITY
                    piece in rewindStart until targetPiece -> Priority.LOW
                    piece in targetPiece..readaheadEnd -> Priority.DEFAULT
                    else -> Priority.IGNORE
                }
                handle.piecePriority(piece, priority)
                if (priority == Priority.TOP_PRIORITY) {
                    handle.setPieceDeadline(piece, if (inTail) 4000 else (piece - targetPiece) * 800)
                }
            }

            val status = handle.status()
            if (status.downloadRate() > 0) lastDataAt = now

            if (now - lastLogAt > 5_000L) {
                lastLogAt = now
                Log.i(
                    "TorrentStream",
                    "rate ${status.downloadRate() / 1024}kB/s, ${status.numPeers()} peers " +
                        "(${status.numSeeds()} seeds), target piece $targetPiece/$lastPiece, " +
                        "blocked=$blocked starving=$starving",
                )
            }

            // Stall watchdog: the piece playback is actually blocked on
            // hasn't arrived after `stallMs` of sitting at the front of the
            // rush window - re-kick it solo rather than waiting for the
            // swarm to satisfy it on its own.
            if (blocked && now - rushSince > stallMs) {
                handle.piecePriority(targetPiece, Priority.TOP_PRIORITY)
                handle.resetPieceDeadline(targetPiece)
                handle.setPieceDeadline(targetPiece, 0)
                rushSince = now
            }

            // Shake: force a fresh tracker/DHT announce to surface peers we
            // aren't currently connected to. Re-kicking a stuck piece's own
            // priority/deadline (above) only helps if some already-connected
            // peer actually has it - in practice the specific piece playback
            // is blocked on can stay stuck for a minute-plus while overall
            // torrent-wide rate looks completely healthy (hundreds of
            // KB/s from everything else), which a dead-swarm-only check
            // (now - lastDataAt, reset by *any* download activity) never
            // catches. Fire this whenever either the whole swarm is quiet
            // or this one piece specifically has been starving.
            if ((now - lastDataAt > starveMs || starving) && now - lastShakeAt > shakeIntervalMs) {
                lastShakeAt = now
                runCatching { handle.forceReannounce() }
                runCatching { handle.forceDHTAnnounce() }
            }
        }
    }
}
