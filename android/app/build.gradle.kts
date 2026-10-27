plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val prepareDebugFailedScanReplayAsset by tasks.registering(Copy::class) {
    val replayBundle = rootProject.file("../talaanscan_failed_capture.zip")
    from(replayBundle)
    into(layout.buildDirectory.dir("generated/debugFailedScanReplayAssets"))
    doFirst {
        check(replayBundle.isFile) {
            "Missing debug replay bundle: ${replayBundle.absolutePath}"
        }
    }
}

android {
    namespace = "com.example.capstone_development"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.capstone_development"
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

    sourceSets.getByName("debug").assets.srcDir(
        layout.buildDirectory.dir("generated/debugFailedScanReplayAssets"),
    )
}

tasks.matching { it.name == "mergeDebugAssets" }.configureEach {
    dependsOn(prepareDebugFailedScanReplayAsset)
}

flutter {
    source = "../.."
}
