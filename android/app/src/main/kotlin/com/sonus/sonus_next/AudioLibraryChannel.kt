package com.sonus.sonus_next

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Read access to the device's music through the standard audio permission
 * (READ_MEDIA_AUDIO, or READ_EXTERNAL_STORAGE before Android 13).
 *
 * Some devices' system folder picker cannot open folders such as
 * Download/Music. With this permission the music can be listed through
 * MediaStore and read by its normal path, as Android allows for media
 * files. It grants no write access and reaches no non-audio files.
 */
class AudioLibraryChannel(
    private val activity: Activity,
    messenger: BinaryMessenger
) {
    private var pendingRequest: MethodChannel.Result? = null

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(if (isGranted()) GRANTED else DENIED)
                "request" -> request(result)
                "openSettings" -> openSettings(result)
                "audioFolders" -> audioFolders(result)
                else -> result.notImplemented()
            }
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != REQUEST_CODE) return false

        val result = pendingRequest ?: return true
        pendingRequest = null

        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED

        result.success(
            when {
                granted -> GRANTED
                // No rationale after a denial means Android will not ask
                // again; only the app's settings page can grant it.
                !activity.shouldShowRequestPermissionRationale(permission) -> BLOCKED
                else -> DENIED
            }
        )
        return true
    }

    private val permission: String
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }

    private fun isGranted(): Boolean =
        activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun request(result: MethodChannel.Result) {
        if (isGranted()) {
            result.success(GRANTED)
            return
        }

        if (pendingRequest != null) {
            result.error("REQUEST_IN_PROGRESS", "A request is already open.", null)
            return
        }

        pendingRequest = result
        activity.requestPermissions(arrayOf(permission), REQUEST_CODE)
    }

    private fun openSettings(result: MethodChannel.Result) {
        try {
            activity.startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", activity.packageName, null)
                )
            )
            result.success(null)
        } catch (error: Exception) {
            result.error("SETTINGS_UNAVAILABLE", "App settings could not be opened.", null)
        }
    }

    /** Each folder that directly holds audio, with its number of files. */
    private fun audioFolders(result: MethodChannel.Result) {
        if (!isGranted()) {
            result.error("PERMISSION_DENIED", "Music access has not been granted.", null)
            return
        }

        Thread {
            try {
                val counts = sortedMapOf<String, Int>()

                @Suppress("DEPRECATION")
                val column = MediaStore.Audio.Media.DATA

                activity.contentResolver.query(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    arrayOf(column),
                    null,
                    null,
                    null
                )?.use { cursor ->
                    val index = cursor.getColumnIndexOrThrow(column)
                    while (cursor.moveToNext()) {
                        val path = cursor.getString(index) ?: continue
                        val parent = File(path).parent ?: continue
                        counts[parent] = (counts[parent] ?: 0) + 1
                    }
                }

                val folders = counts.map { (path, count) ->
                    mapOf("path" to path, "audioCount" to count)
                }
                activity.runOnUiThread { result.success(folders) }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    result.error("QUERY_FAILED", "Music folders could not be listed.", null)
                }
            }
        }.start()
    }

    companion object {
        const val CHANNEL = "com.sonus.sonus_next/audio_library"
        private const val REQUEST_CODE = 4107
        private const val GRANTED = "granted"
        private const val DENIED = "denied"
        private const val BLOCKED = "blocked"
    }
}
