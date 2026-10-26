import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.ark.theater.ark_theater"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // lintVitalAnalyzeRelease runs a static-analysis pass over release
    // builds and produces nothing that ends up in the APK. On Windows it
    // repeatedly failed the whole build with
    // "The process cannot access the file because it is being used by
    // another process" on its own lint-cache jars - a stale Gradle daemon
    // or antivirus still holding a handle. Turning it off removes that
    // failure mode (and a chunk of build time); run `flutter analyze` for
    // real code analysis instead, which is faster and platform-neutral.
    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }

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
            // A GitHub Release must always use the same certificate as the
            // installed app, otherwise Android refuses it as an update.
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.create("release") {
                    keyAlias = keystoreProperties.getProperty("keyAlias")
                    keyPassword = keystoreProperties.getProperty("keyPassword")
                    storeFile = file(keystoreProperties.getProperty("storeFile"))
                    storePassword = keystoreProperties.getProperty("storePassword")
                }
            } else {
                // Keeps local development builds working before the private
                // key.properties file is configured. CI always supplies one.
                signingConfig = signingConfigs.getByName("debug")
            }
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
