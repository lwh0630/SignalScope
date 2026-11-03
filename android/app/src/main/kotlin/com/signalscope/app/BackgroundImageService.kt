package com.signalscope.app

import android.app.Activity
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

/**
 * Lets the user pick a picture for the app background through the system
 * document picker (no storage permission needed) and keeps a private copy of it.
 *
 * Every pick is written under a fresh file name inside `filesDir/backgrounds`,
 * so Flutter's image cache never serves a stale picture; Dart deletes the
 * previous one through [delete]. Only model-free file bytes are handled here.
 */
class BackgroundImageService(private val activity: Activity) {

    companion object {
        const val REQUEST_CODE = 7421
        private const val MAX_BYTES = 40L * 1024 * 1024
    }

    private val dir = File(activity.filesDir, "backgrounds")
    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null

    fun pick(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "A picture is already being chosen", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("image/*")
        pending = result
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (t: Throwable) {
            pending = null
            result.error("native_error", t.message, null)
        }
    }

    /** Returns true when the result belonged to the picker. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pending ?: return true
        pending = null
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri == null) {
            result.success(null)
            return true
        }
        // Copy off the main thread; reply on it.
        Thread {
            val outcome = try {
                Result.success(copy(uri))
            } catch (t: Throwable) {
                Result.failure(t)
            }
            main.post {
                outcome.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { result.error("image_failed", it.message, null) },
                )
            }
        }.start()
        return true
    }

    private fun copy(uri: Uri): String {
        dir.mkdirs()
        val target = File(dir, "bg_${System.currentTimeMillis()}.img")
        try {
            val input = activity.contentResolver.openInputStream(uri)
                ?: throw IOException("The picture cannot be opened")
            input.use { src ->
                target.outputStream().use { dst ->
                    val buffer = ByteArray(64 * 1024)
                    var total = 0L
                    while (true) {
                        val n = src.read(buffer)
                        if (n < 0) break
                        total += n
                        if (total > MAX_BYTES) throw IOException("The picture is too large")
                        dst.write(buffer, 0, n)
                    }
                }
            }
            // Must be a decodable picture; this reads only the header.
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(target.path, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
                throw IOException("This file is not a picture")
            }
            return target.path
        } catch (t: Throwable) {
            target.delete()
            throw t
        }
    }

    /** Deletes [path] if, and only if, it is a file inside the background folder. */
    fun delete(path: String?) {
        if (path.isNullOrEmpty()) return
        try {
            val file = File(path).canonicalFile
            if (file.parentFile == dir.canonicalFile && file.isFile) file.delete()
        } catch (_: Throwable) {
            // best effort
        }
    }
}
