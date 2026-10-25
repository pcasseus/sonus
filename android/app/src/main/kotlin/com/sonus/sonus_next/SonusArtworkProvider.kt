package com.sonus.sonus_next

import android.content.ContentProvider
import android.content.ContentValues
import android.content.pm.ApplicationInfo
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException

/**
 * SN-45: serves Sonus's managed artwork to Android Auto.
 *
 * Car hosts run in another app and cannot open Sonus's private files, so
 * browse and queue artwork is offered as
 * `content://com.sonus.sonus_next.artwork/<file name>`
 * (ArtworkContentUris.dart builds the same URIs).
 *
 * Read-only, and deliberately narrow:
 * - only single file names matching the managed-artwork pattern, directly
 *   inside `files/sonus/artwork`, and never a path that resolves elsewhere;
 * - only callers on [TRUSTED_CALLERS] (the car and system media hosts) or
 *   Sonus itself. Debuggable builds also accept [DEBUG_TEST_CLIENT], the
 *   disposable media-browser test client used for SN-45 verification.
 *
 * Nothing can be written, listed or queried.
 */
class SonusArtworkProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") {
            throw SecurityException("Sonus artwork is read-only.")
        }

        val context = context ?: throw FileNotFoundException("Not ready.")
        val caller = callingPackage

        if (!isTrustedCaller(caller, context.packageName, context.applicationInfo)) {
            Log.w(TAG, "Artwork request refused for caller=$caller")
            throw SecurityException("This app may not read Sonus artwork.")
        }

        val file = resolve(File(context.filesDir, ARTWORK_DIRECTORY), uri)
            ?: throw FileNotFoundException("Artwork not found.")

        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri): String? {
        val name = uri.pathSegments.singleOrNull() ?: return null
        return when (name.substringAfterLast('.', "").lowercase()) {
            "png" -> "image/png"
            "webp" -> "image/webp"
            "jpg", "jpeg" -> "image/jpeg"
            else -> "image/*"
        }
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? =
        throw UnsupportedOperationException("Sonus artwork is read-only.")

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int =
        throw UnsupportedOperationException("Sonus artwork is read-only.")

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int = throw UnsupportedOperationException("Sonus artwork is read-only.")

    companion object {
        private const val TAG = "SonusArtworkProvider"

        const val ARTWORK_DIRECTORY = "sonus/artwork"

        /** Matches FileSystemArtworkManagedStorage's file names. */
        private val FILE_NAME = Regex("^artwork_[A-Za-z0-9_-]+\\.[A-Za-z0-9]{1,5}$")

        /**
         * Hosts that draw Sonus's media browser: Android Auto on the phone,
         * the Android Automotive OS media center, and the system media
         * controls.
         */
        val TRUSTED_CALLERS = setOf(
            "com.google.android.projection.gearhead",
            "com.android.car.media",
            "com.google.android.carassistant",
            "com.android.systemui",
        )

        /** Accepted only by debuggable builds. */
        const val DEBUG_TEST_CLIENT = "com.sonus.autotest"

        fun isTrustedCaller(
            caller: String?,
            ownPackage: String,
            appInfo: ApplicationInfo
        ): Boolean {
            if (caller == null) return false
            if (caller == ownPackage || caller in TRUSTED_CALLERS) return true
            val debuggable = (appInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            return debuggable && caller == DEBUG_TEST_CLIENT
        }

        /** The artwork file [uri] names, or null if it is not one. */
        fun resolve(directory: File, uri: Uri): File? {
            val name = uri.pathSegments.singleOrNull() ?: return null
            if (!FILE_NAME.matches(name)) return null

            return try {
                val root = directory.canonicalFile
                val file = File(root, name).canonicalFile
                if (file.parentFile != root || !file.isFile) null else file
            } catch (error: IOException) {
                null
            }
        }
    }
}
