plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.ark.theater.ark_theater"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ark.theater.ark_theater"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// better_player_plus 1.0.8 (uz.shs.better_player_plus) is compiled against
// androidx.media3 1.3.1 and calls the (since-removed) ExoPlayer.getAudioComponent()
// API directly. video_player_android 2.9.5 - pulled in only because the `video_player`
// package is a direct dependency (used solely for the macOS backend in
// macos_player_screen.dart; its Android implementation is never actually invoked) -
// separately requests androidx.media3 1.9.2. Gradle's default "highest version wins"
// resolution then upgrades every androidx.media3 artifact app-wide to 1.9.2, whose
// ExoPlayer no longer has getAudioComponent() at all, so BetterPlayer's constructor
// crashes with NoSuchMethodError the moment playback starts. Forcing the whole
// androidx.media3 group back to 1.3.1 here keeps it on the version better_player_plus
// actually compiles against; video_player_android never runs on this platform anyway,
// so downgrading its unused media3 usage is safe.
configurations.all {
    resolutionStrategy.eachDependency {
        if (requested.group == "androidx.media3") {
            useVersion("1.3.1")
            because(
                "better_player_plus 1.0.8 needs media3 1.3.1's ExoPlayer.getAudioComponent(); " +
                    "later media3 removes it, crashing playback with NoSuchMethodError."
            )
        }
    }
}

flutter {
    source = "../.."
}
