package com.ark.theater.ark_theater

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
    }
}
