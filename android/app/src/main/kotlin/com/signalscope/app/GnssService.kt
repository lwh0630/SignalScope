package com.signalscope.app

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.GnssStatus
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.Executor

/**
 * GNSS location and satellite status.
 *
 * Everything comes from the public platform APIs:
 *  * `LocationManager.requestLocationUpdates(GPS_PROVIDER)` for the fix (pure GNSS, no network provider).
 *  * `GnssStatus.Callback` for satellites, C/N0, used-in-fix flags and TTFF.
 *
 * Listeners exist only while the Flutter side is subscribed. TTFF is the value
 * reported by `onFirstFixReceived` for the current subscription; if the chipset
 * already had a fix when we subscribed, no TTFF is reported and the value stays null.
 */
class GnssService(private val context: Context) {

    companion object {
        private const val EMIT_COALESCE_MS = 250L
        private const val MIN_TIME_MS = 1000L
    }

    private val locationManager: LocationManager? =
        context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
    private val handler = Handler(Looper.getMainLooper())
    private val mainExecutor = Executor { handler.post(it) }

    private var sink: EventChannel.EventSink? = null
    private var locationListener: LocationListener? = null
    private var statusCallback: GnssStatus.Callback? = null

    private var location: Location? = null
    private var satellites: List<Map<String, Any?>> = emptyList()
    private var ttffMs: Int? = null
    private var engineStarted: Boolean? = null
    private var emitScheduled = false

    private val emit = Runnable {
        emitScheduled = false
        sink?.success(buildSnapshot())
    }

    private fun hasGnssHardware(): Boolean {
        val pm = context.packageManager
        return pm.hasSystemFeature(PackageManager.FEATURE_LOCATION_GPS) ||
            pm.hasSystemFeature("android.hardware.location.gnss")
    }

    private fun providerEnabled(): Boolean? = safe {
        locationManager?.isProviderEnabled(LocationManager.GPS_PROVIDER)
    }

    fun start(sink: EventChannel.EventSink) {
        stop()
        this.sink = sink
        location = null
        satellites = emptyList()
        ttffMs = null
        engineStarted = null

        val lm = locationManager
        if (lm == null || !hasGnssHardware() || !Perms.hasFineLocation(context)) {
            // Nothing to register; report why instead of staying silent.
            sink.success(buildSnapshot())
            return
        }
        registerListeners(lm)
        sink.success(buildSnapshot())
    }

    @SuppressLint("MissingPermission")
    private fun registerListeners(lm: LocationManager) {
        val locListener = object : LocationListener {
            override fun onLocationChanged(loc: Location) {
                location = loc
                scheduleEmit()
            }

            override fun onProviderEnabled(provider: String) = scheduleEmit()

            override fun onProviderDisabled(provider: String) {
                if (provider == LocationManager.GPS_PROVIDER) location = null
                scheduleEmit()
            }

            @Deprecated("Deprecated in Java")
            @Suppress("OVERRIDE_DEPRECATION")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {
            }
        }
        try {
            lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, MIN_TIME_MS, 0f, locListener, Looper.getMainLooper())
            locationListener = locListener
        } catch (_: IllegalArgumentException) {
            // No GPS provider on this device.
        }

        val callback = object : GnssStatus.Callback() {
            override fun onStarted() {
                engineStarted = true
                scheduleEmit()
            }

            override fun onStopped() {
                engineStarted = false
                satellites = emptyList()
                scheduleEmit()
            }

            override fun onFirstFix(ttffMillis: Int) {
                ttffMs = ttffMillis
                scheduleEmit()
            }

            override fun onSatelliteStatusChanged(status: GnssStatus) {
                satellites = mapSatellites(status)
                scheduleEmit()
            }
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                lm.registerGnssStatusCallback(mainExecutor, callback)
                statusCallback = callback
            } else {
                @Suppress("DEPRECATION")
                if (lm.registerGnssStatusCallback(callback, handler)) statusCallback = callback
            }
        } catch (_: SecurityException) {
        }
    }

    fun stop() {
        handler.removeCallbacks(emit)
        emitScheduled = false
        val lm = locationManager
        locationListener?.let { l -> safe { lm?.removeUpdates(l) } }
        statusCallback?.let { c -> safe { lm?.unregisterGnssStatusCallback(c) } }
        locationListener = null
        statusCallback = null
        sink = null
    }

    fun dispose() {
        stop()
    }

    private fun scheduleEmit() {
        if (sink == null || emitScheduled) return
        emitScheduled = true
        handler.postDelayed(emit, EMIT_COALESCE_MS)
    }

    private fun mapSatellites(status: GnssStatus): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>(status.satelliteCount)
        for (i in 0 until status.satelliteCount) {
            val hasCarrier = status.hasCarrierFrequencyHz(i)
            val hasBaseband = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && status.hasBasebandCn0DbHz(i)
            out += mapOf(
                "svid" to status.getSvid(i),
                "constellation" to status.getConstellationType(i),
                "azimuthDeg" to status.getAzimuthDegrees(i).toDouble(),
                "elevationDeg" to status.getElevationDegrees(i).toDouble(),
                "cn0DbHz" to status.getCn0DbHz(i).toDouble(),
                "usedInFix" to status.usedInFix(i),
                "carrierFrequencyHz" to if (hasCarrier) status.getCarrierFrequencyHz(i).toDouble() else null,
                "basebandCn0DbHz" to if (hasBaseband) status.getBasebandCn0DbHz(i).toDouble() else null,
            )
        }
        return out
    }

    private fun mapLocation(loc: Location): Map<String, Any?> {
        val mock = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            loc.isMock
        } else {
            @Suppress("DEPRECATION")
            loc.isFromMockProvider
        }
        return mapOf(
            "latitude" to loc.latitude,
            "longitude" to loc.longitude,
            "altitudeM" to if (loc.hasAltitude()) loc.altitude else null,
            "horizontalAccuracyM" to if (loc.hasAccuracy()) loc.accuracy.toDouble() else null,
            "verticalAccuracyM" to if (loc.hasVerticalAccuracy()) loc.verticalAccuracyMeters.toDouble() else null,
            "speedMps" to if (loc.hasSpeed()) loc.speed.toDouble() else null,
            "bearingDeg" to if (loc.hasBearing()) loc.bearing.toDouble() else null,
            "timeMs" to loc.time,
            "provider" to loc.provider,
            "isMock" to mock,
        )
    }

    private fun buildSnapshot(): Map<String, Any?> {
        val issues = ArrayList<String>()
        val supported = hasGnssHardware()
        val permitted = Perms.hasFineLocation(context)
        val locationOn = Perms.isLocationEnabled(context)
        val provider = if (supported && permitted) providerEnabled() else null
        if (!supported) issues += "gnss_unsupported"
        if (supported && !permitted) issues += "no_location_permission"
        if (supported && permitted && locationOn == false) issues += "location_off"
        if (supported && permitted && locationOn != false && provider == false) issues += "gps_provider_disabled"
        return mapOf(
            "timestampMs" to System.currentTimeMillis(),
            "location" to location?.let { mapLocation(it) },
            "satellites" to satellites,
            "ttffMs" to ttffMs,
            "gnssSupported" to supported,
            "providerEnabled" to provider,
            "engineStarted" to engineStarted,
            "issues" to issues,
        )
    }
}
