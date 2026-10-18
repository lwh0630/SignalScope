package com.signalscope.app

import android.content.ContentValues
import android.content.Context
import android.os.Environment
import android.provider.MediaStore

/**
 * Saves exported CSV / JSON text into the public Downloads folder using
 * MediaStore (no storage permission needed on Android 10+).
 */
class ExportService(private val context: Context) {

    /** Returns a human readable location, or throws on failure. */
    fun save(fileName: String, mimeType: String, content: String): String {
        val safeName = fileName.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        val relativePath = Environment.DIRECTORY_DOWNLOADS + "/SignalScope"
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("MediaStore insert returned null")
        try {
            resolver.openOutputStream(uri)?.use { out ->
                out.write(content.toByteArray(Charsets.UTF_8))
            } ?: throw IllegalStateException("Cannot open output stream")
            val done = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            resolver.update(uri, done, null, null)
        } catch (t: Throwable) {
            resolver.delete(uri, null, null)
            throw t
        }
        return "$relativePath/$safeName"
    }
}
