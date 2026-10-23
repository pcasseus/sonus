package com.sonus.sonus_next

import android.content.Intent
import android.os.StatFs
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val publicationChannel =
        "com.sonus.sonus_next/backup_publication"

    private val storageChannel = "com.sonus.sonus_next/storage"

    private var backupDocuments: BackupDocumentChannel? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (backupDocuments?.onActivityResult(requestCode, resultCode, data) == true) {
            return
        }

        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        backupDocuments = BackupDocumentChannel(
            this,
            flutterEngine.dartExecutor.binaryMessenger
        )

        AppInfoChannel(this, flutterEngine.dartExecutor.binaryMessenger)

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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            storageChannel
        ).setMethodCallHandler { call, result ->
            if (call.method != "availableBytes") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val path = call.argument<String>("path")

            if (path.isNullOrBlank()) {
                result.error("INVALID_PATH", "A storage path is required.", null)
                return@setMethodCallHandler
            }

            try {
                // Space available to this app on the volume holding the path.
                result.success(StatFs(path).availableBytes)
            } catch (error: Exception) {
                result.error(
                    "STORAGE_QUERY_FAILED",
                    "Free storage could not be determined.",
                    null
                )
            }
        }
    }
}