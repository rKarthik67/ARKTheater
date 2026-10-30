package com.ark.theater.ark_theater

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Adds one platform channel so Dart-side layout code
 * (lib/core/responsive.dart's Responsive.initDeviceType()) can ask whether
 * this device is Android TV or Amazon Fire TV, to decide bottom nav bar
 * (phones/tablets, remote-free/touch) vs. side NavigationRail (TV, driven
 * by a D-pad remote where a rail down the left edge is far easier to
 * navigate to than a bar hugging the bottom edge of a living-room TV).
 *
 * FEATURE_LEANBACK is the standard Android TV system feature, and Amazon
 * Fire TV also declares it (Fire OS is an AOSP fork built to run Leanback
 * launcher apps), so this single check covers both Google Android TV and
 * Fire TV/Firestick without separate Amazon-specific logic.
 */
class MainActivity : FlutterActivity() {
    private val deviceTypeChannel = "ark_theater/device_type"
    private val updateChannel = "ark_theater/update"
    private val torrentChannel = "ark_theater/torrent"
    private val torrentStatusChannel = "ark_theater/torrent_status"
    private val torrentExecutor = Executors.newSingleThreadExecutor()
    @Volatile private var torrentStatusSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceTypeChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "isTv") {
                    val isTv = packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
                    result.success(isTv)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstallPackages" -> {
                        result.success(packageManager.canRequestPackageInstalls())
                    }
                    "requestInstallPermission" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            )
                        )
                        result.success(null)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("invalid_path", "Missing APK path.", null)
                            return@setMethodCallHandler
                        }
                        val apk = File(path)
                        if (!apk.isFile) {
                            result.error("missing_apk", "Downloaded APK no longer exists.", null)
                            return@setMethodCallHandler
                        }
                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileprovider",
                            apk
                        )
                        startActivity(
                            Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, torrentChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "startMagnet") {
                    if (call.method == "queueDownload") {
                        val magnet = call.argument<String>("magnet")
                        if (magnet.isNullOrBlank()) {
                            result.error("invalid_magnet", "Missing magnet URI.", null)
                        } else {
                            torrentExecutor.execute {
                                try {
                                    TorrentStreamManager.queueDownload(applicationContext, magnet)
                                    runOnUiThread { result.success(null) }
                                } catch (error: Throwable) {
                                    runOnUiThread { result.error("torrent_download_failed", error.message, null) }
                                }
                            }
                        }
                        return@setMethodCallHandler
                    }
                    if (call.method == "warmUp") {
                        torrentExecutor.execute {
                            try {
                                TorrentStreamManager.warmUp(applicationContext)
                                runOnUiThread { result.success(null) }
                            } catch (error: Throwable) {
                                runOnUiThread { result.error("torrent_warmup_failed", error.message, null) }
                            }
                        }
                        return@setMethodCallHandler
                    }
                    if (call.method == "playExternalVlc") {
                        val url = call.argument<String>("url")
                        val title = call.argument<String>("title") ?: "Torrent source"
                        if (url.isNullOrBlank()) {
                            result.error("invalid_stream", "Missing local torrent stream.", null)
                            return@setMethodCallHandler
                        }
                        val vlcIntent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(Uri.parse(url), "video/*")
                            setPackage("org.videolan.vlc")
                            putExtra("title", title)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        if (vlcIntent.resolveActivity(packageManager) == null) {
                            result.error("vlc_not_installed", "Install the VLC Android app to use this option.", null)
                        } else {
                            startActivity(vlcIntent)
                            result.success(null)
                        }
                        return@setMethodCallHandler
                    }
                    if (call.method == "clearCache") {
                        torrentExecutor.execute {
                            try {
                                TorrentStreamManager.clearCache(applicationContext)
                                runOnUiThread { result.success(null) }
                            } catch (error: Throwable) {
                                runOnUiThread { result.error("torrent_clear_failed", error.message, null) }
                            }
                        }
                        return@setMethodCallHandler
                    }
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val magnet = call.argument<String>("magnet")
                if (magnet.isNullOrBlank()) {
                    result.error("invalid_magnet", "Missing magnet URI.", null)
                    return@setMethodCallHandler
                }
                val fileIndex = call.argument<Int>("fileIndex")
                torrentExecutor.execute {
                    try {
                        val stream = TorrentStreamManager.startMagnet(applicationContext, magnet, fileIndex) { status ->
                            runOnUiThread { torrentStatusSink?.success(status) }
                        }
                        runOnUiThread { result.success(stream) }
                    } catch (error: Throwable) {
                        runOnUiThread {
                            result.error("torrent_start_failed", error.message ?: error.javaClass.simpleName, null)
                        }
                    }
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, torrentStatusChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    torrentStatusSink = events
                }

                override fun onCancel(arguments: Any?) {
                    torrentStatusSink = null
                }
            })
    }
}
