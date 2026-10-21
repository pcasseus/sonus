package com.sonus.sonus_next

import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val publicationChannel =
        "com.sonus.sonus_next/backup_publication"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            publicationChannel
        ).setMethodCallHandler { call, result ->
            if (call.method != "publishNoReplace") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val source = call.argument<String>("source")
            val destination = call.argument<String>("destination")

            if (source.isNullOrBlank() || destination.isNullOrBlank()) {
                result.error(
                    "INVALID_PATH",
                    "Backup paths are required.",
                    null
                )
                return@setMethodCallHandler
            }

            try {
                // Publish a verified candidate without replacing a target.
                Os.link(source, destination)
                result.success(null)
            } catch (error: ErrnoException) {
                if (error.errno == OsConstants.EEXIST) {
                    result.error(
                        "DESTINATION_EXISTS",
                        "Backup destination already exists.",
                        null
                    )
                } else {
                    result.error(
                        "PUBLICATION_FAILED",
                        "Atomic backup publication failed: ${error.errno}",
                        null
                    )
                }
            } catch (error: Exception) {
                result.error(
                    "PUBLICATION_FAILED",
                    "Atomic backup publication failed.",
                    null
                )
            }
        }
    }
}