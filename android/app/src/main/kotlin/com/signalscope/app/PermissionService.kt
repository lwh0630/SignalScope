package com.signalscope.app

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build

/** Stateless permission checks shared by every native service. */
object Perms {
    fun has(context: Context, permission: String): Boolean =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    fun hasFineLocation(context: Context) = has(context, Manifest.permission.ACCESS_FINE_LOCATION)

    fun hasPhoneState(context: Context) = has(context, Manifest.permission.READ_PHONE_STATE)

    /** NEARBY_WIFI_DEVICES only exists on Android 13+. */
    fun hasNearbyWifi(context: Context): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            has(context, Manifest.permission.NEARBY_WIFI_DEVICES)

    /** Whether the system-wide location switch is on. */
    fun isLocationEnabled(context: Context): Boolean? {
        return try {
            val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return null
            lm.isLocationEnabled
        } catch (e: SecurityException) {
            null
        }
    }
}

/**
 * Runtime permission handling for the three permission groups used by the app.
 *
 * Groups: `location` (fine + coarse), `phone` (READ_PHONE_STATE) and
 * `nearbyWifi` (NEARBY_WIFI_DEVICES, Android 13+).
 *
 * "Permanently denied" is detected as: not granted, the system will not show the
 * rationale, and we have already asked at least once.
 */
class PermissionService(private val activity: Activity) {

    companion object {
        const val REQUEST_CODE = 7001
        private const val PREFS = "signalscope_permissions"
    }

    private val prefs = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private var pending: ((Map<String, Any?>) -> Unit)? = null

    private fun permissionsFor(group: String): List<String> = when (group) {
        "location" -> listOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        )
        "phone" -> listOf(Manifest.permission.READ_PHONE_STATE)
        "nearbyWifi" ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                listOf(Manifest.permission.NEARBY_WIFI_DEVICES)
            } else {
                emptyList()
            }
        else -> emptyList()
    }

    private fun statusOf(group: String): String {
        val perms = permissionsFor(group)
        if (perms.isEmpty()) return "notApplicable"
        // Precise location is what every feature needs; coarse-only is not enough.
        val required = if (group == "location") listOf(Manifest.permission.ACCESS_FINE_LOCATION) else perms
        if (required.all { Perms.has(activity, it) }) return "granted"
        val askedBefore = perms.any { prefs.getBoolean("asked_$it", false) }
        val canAskAgain = perms.any { activity.shouldShowRequestPermissionRationale(it) }
        return if (askedBefore && !canAskAgain) "permanentlyDenied" else "denied"
    }

    fun snapshot(): Map<String, Any?> = mapOf(
        "location" to statusOf("location"),
        "phone" to statusOf("phone"),
        "nearbyWifi" to statusOf("nearbyWifi"),
        "locationServicesEnabled" to Perms.isLocationEnabled(activity),
    )

    /** Requests every not-yet-granted permission in [groups]; [callback] receives a fresh snapshot. */
    fun request(groups: List<String>, callback: (Map<String, Any?>) -> Unit) {
        val toRequest = groups
            .flatMap { permissionsFor(it) }
            .distinct()
            .filter { !Perms.has(activity, it) }
        if (toRequest.isEmpty()) {
            callback(snapshot())
            return
        }
        // A newer request supersedes an unanswered one.
        pending?.invoke(snapshot())
        pending = callback
        activity.requestPermissions(toRequest.toTypedArray(), REQUEST_CODE)
    }

    fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>) {
        if (requestCode != REQUEST_CODE) return
        val editor = prefs.edit()
        permissions.forEach { editor.putBoolean("asked_$it", true) }
        editor.apply()
        val cb = pending
        pending = null
        cb?.invoke(snapshot())
    }

    fun dispose() {
        pending = null
    }
}
