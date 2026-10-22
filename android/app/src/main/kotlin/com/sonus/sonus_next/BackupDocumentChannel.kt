package com.sonus.sonus_next

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.security.MessageDigest
import java.util.concurrent.Executors

/**
 * Saves a verified backup to a user-chosen document (Downloads, Drive, USB)
 * through the Storage Access Framework, then reads it back so Dart can
 * compare its SHA-256 with the source. File I/O runs off the main thread.
 */
class BackupDocumentChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "com.sonus.sonus_next/backup_export"
        const val CREATE_DOCUMENT_REQUEST = 4127
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingCreate: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createDocument" -> createDocument(call, result)
            "writeDocument" -> writeDocument(call, result)
            "readBackDocument" -> readBackDocument(call, result)
            "deleteDocument" -> deleteDocument(call, result)
            else -> result.notImplemented()
        }
    }

    private fun createDocument(call: MethodCall, result: MethodChannel.Result) {
        val name = call.argument<String>("suggestedName")

        if (name.isNullOrBlank()) {
            result.error("INVALID_NAME", "A file name is required.", null)
            return
        }

        if (pendingCreate != null) {
            result.error("BUSY", "A save dialog is already open.", null)
            return
        }

        pendingCreate = result

        try {
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/octet-stream"
                putExtra(Intent.EXTRA_TITLE, name)
            }
            activity.startActivityForResult(intent, CREATE_DOCUMENT_REQUEST)
        } catch (error: Exception) {
            pendingCreate = null
            result.error("PICKER_UNAVAILABLE", "No document picker is available.", null)
        }
    }

    /** Returns true when the result belonged to this channel. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != CREATE_DOCUMENT_REQUEST) return false

        val result = pendingCreate ?: return true
        pendingCreate = null

        val uri = data?.data
        // Cancellation is reported as null, never as a saved document.
        result.success(if (resultCode == Activity.RESULT_OK && uri != null) uri.toString() else null)
        return true
    }

    private fun writeDocument(call: MethodCall, result: MethodChannel.Result) {
        val source = call.argument<String>("source")
        val uri = call.argument<String>("uri")

        if (source.isNullOrBlank() || uri.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "Source and document are required.", null)
            return
        }

        io.execute {
            try {
                var written = 0L
                val output = activity.contentResolver.openOutputStream(Uri.parse(uri), "w")
                    ?: throw FileNotFoundException("Document cannot be opened.")

                output.use { out ->
                    FileInputStream(File(source)).use { input ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            val read = input.read(buffer)
                            if (read < 0) break
                            out.write(buffer, 0, read)
                            written += read
                        }
                    }
                    out.flush()
                }

                main.post { result.success(written) }
            } catch (error: Exception) {
                main.post { result.error("WRITE_FAILED", "The backup could not be saved.", null) }
            }
        }
    }

    private fun readBackDocument(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")

        if (uri.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "A document is required.", null)
            return
        }

        io.execute {
            try {
                val input = activity.contentResolver.openInputStream(Uri.parse(uri))

                if (input == null) {
                    main.post {
                        result.error("READ_BACK_UNAVAILABLE", "The provider does not allow reading.", null)
                    }
                    return@execute
                }

                val digest = MessageDigest.getInstance("SHA-256")
                var length = 0L

                input.use { stream ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = stream.read(buffer)
                        if (read < 0) break
                        digest.update(buffer, 0, read)
                        length += read
                    }
                }

                val hex = digest.digest().joinToString("") { "%02x".format(it) }
                main.post { result.success(mapOf("sha256" to hex, "length" to length)) }
            } catch (error: SecurityException) {
                main.post {
                    result.error("READ_BACK_UNAVAILABLE", "The provider does not allow reading.", null)
                }
            } catch (error: Exception) {
                main.post { result.error("READ_BACK_FAILED", "The saved backup could not be read.", null) }
            }
        }
    }

    private fun deleteDocument(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")

        if (uri.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "A document is required.", null)
            return
        }

        io.execute {
            val deleted = try {
                DocumentsContract.deleteDocument(activity.contentResolver, Uri.parse(uri))
            } catch (error: Exception) {
                false
            }
            main.post { result.success(deleted) }
        }
    }
}
