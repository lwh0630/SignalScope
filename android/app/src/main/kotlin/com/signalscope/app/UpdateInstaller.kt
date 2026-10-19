package com.signalscope.app

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.FileProvider
import java.io.File
import java.security.MessageDigest

/**
 * Native half of the in-app updater. Dart downloads the APK (`dart:io`) into the
 * private directory returned by [prepareDir]; this class only
 *  * reports the installed version and the device ABIs,
 *  * re-verifies the file right before installing it (SHA-256, package name,
 *    newer version code, same signing certificate as the installed app),
 *  * hands the file to the system package installer.
 *
 * Public SDK APIs only. The system installer asks the user for confirmation, and
 * Android itself refuses an APK that is not signed with the installed app's key.
 */
class UpdateInstaller(private val context: Context) {

    companion object {
        private const val DIR_NAME = "updates"
        const val PROVIDER_SUFFIX = ".updates"
    }

    private val pm: PackageManager = context.packageManager

    private fun updateDir() = File(context.cacheDir, DIR_NAME)

    fun buildInfo(): Map<String, Any?> {
        val info = pm.getPackageInfo(context.packageName, 0)
        return mapOf(
            "versionName" to info.versionName,
            "versionCode" to info.longVersionCode,
            "supportedAbis" to Build.SUPPORTED_ABIS.toList(),
        )
    }

    /** Creates the (app-private, cache) download directory, emptied of old downloads. */
    fun prepareDir(): String {
        val dir = updateDir()
        dir.mkdirs()
        dir.listFiles()?.forEach { it.deleteRecursively() }
        return dir.absolutePath
    }

    fun canInstallPackages(): Boolean = pm.canRequestPackageInstalls()

    /**
     * Returns one of: `started`, `need_permission`, `hash_mismatch`,
     * `signature_mismatch`, `not_newer`, `bad_apk`, `failed`.
     */
    fun install(path: String, expectedSha256: String): String {
        val file = File(path)
        val dirPath = updateDir().canonicalPath + File.separator
        // Only files this class' directory can contain are ever installed.
        if (!file.canonicalPath.startsWith(dirPath)) return "failed"
        if (!file.isFile) return "bad_apk"

        if (!sha256(file).equals(expectedSha256, ignoreCase = true)) return "hash_mismatch"

        val flags = PackageManager.GET_SIGNING_CERTIFICATES
        val archive = pm.getPackageArchiveInfo(path, flags) ?: return "bad_apk"
        if (archive.packageName != context.packageName) return "bad_apk"

        val installed = pm.getPackageInfo(context.packageName, flags)
        if (archive.longVersionCode <= installed.longVersionCode) return "not_newer"

        val archiveSigners = signerDigests(archive) ?: return "bad_apk"
        val installedSigners = signerDigests(installed) ?: return "failed"
        if (archiveSigners != installedSigners) return "signature_mismatch"

        if (!canInstallPackages()) return "need_permission"

        val uri = FileProvider.getUriForFile(context, context.packageName + PROVIDER_SUFFIX, file)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        return "started"
    }

    private fun signerDigests(info: android.content.pm.PackageInfo): Set<String>? {
        val signers = info.signingInfo?.apkContentsSigners ?: return null
        if (signers.isEmpty()) return null
        return signers.map { hex(MessageDigest.getInstance("SHA-256").digest(it.toByteArray())) }.toSet()
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                digest.update(buffer, 0, n)
            }
        }
        return hex(digest.digest())
    }

    private fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it) }
}
