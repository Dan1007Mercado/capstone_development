package com.example.capstone_development

import android.content.pm.ApplicationInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val debuggable = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        if (!debuggable) return

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.capstone_development/debug_replay",
        ).setMethodCallHandler { call, result ->
            if (call.method != "loadBundledFailedScanCapture") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                result.success(assets.open("talaanscan_failed_capture.zip").use { it.readBytes() })
            } catch (error: Exception) {
                result.error(
                    "DEBUG_REPLAY_ASSET_UNAVAILABLE",
                    "Unable to load the bundled failed-scan replay.",
                    error.toString(),
                )
            }
        }
    }
}
