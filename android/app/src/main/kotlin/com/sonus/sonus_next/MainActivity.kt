package com.sonus.sonus_next

import android.content.Intent
import android.os.StatFs
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import com.ryanheise.audioservice.AudioServiceActivity
import com.ryanheise.audioservice.SonusForegroundRelease
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// SN-44: AudioServiceActivity provides the Flutter engine that audio_service
// keeps alive with its media service, so playback, the coordinator and
// listening analytics continue when this activity is destroyed in the
// background. Channels below are re-registered on each new activity.
class MainActivity : AudioServiceActivity() {
    private val publicationChannel =
        "com.sonus.sonus_next/backup_publication"

    private val storageChannel = "com.sonus.sonus_next/storage"

    private val mediaSessionChannel = "com.sonus.sonus_next/media_session"

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

        // Uses no activity, so it is deliberately left registered in
        // cleanUpFlutterEngine: a session can end while no activity exists.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            mediaSessionChannel
        ).setMethodCallHandler { call, result ->
            if (call.method != "releaseForeground") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            result.success(SonusForegroundRelease.release())
        }

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

    // With audio_service the Flutter engine outlives this activity. Detach
    // every channel that depends on it, so a call made while no activity
    // exists fails (MissingPluginException) instead of reaching a destroyed
    // activity. Before SN-44 such calls could not happen at all, because
    // the engine was destroyed with the activity. The next activity
    // registers the channels again in configureFlutterEngine.
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        for (channel in listOf(
            publicationChannel,
            storageChannel,
            BackupDocumentChannel.CHANNEL,
            AppInfoChannel.CHANNEL
        )) {
            MethodChannel(messenger, channel).setMethodCallHandler(null)
        }

        backupDocuments = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
