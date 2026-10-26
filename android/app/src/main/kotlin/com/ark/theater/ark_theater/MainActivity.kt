package com.ark.theater.ark_theater

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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
    }
}
