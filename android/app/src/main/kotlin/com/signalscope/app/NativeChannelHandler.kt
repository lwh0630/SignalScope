package com.signalscope.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.location.LocationManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Single entry point between Flutter and the native services.
 *
 * * MethodChannel `signalscope/method` - one-shot queries and actions.
 * * EventChannels - real-time streams. Each stream registers its system
 *   listeners in `onListen` and unregisters them in `onCancel`, so nothing runs
 *   while Flutter is not subscribed.
 */
class NativeChannelHandler(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val METHOD = "signalscope/method"
        const val CELLULAR = "signalscope/cellular"
        const val WIFI = "signalscope/wifi"
        const val WIFI_SCAN = "signalscope/wifi_scan"
        const val GNSS = "signalscope/gnss"
        private const val SETTINGS_PREFS = "signalscope_settings"
        private const val SETTINGS_KEY = "app_settings_json"
    }

    private val appContext: Context = activity.applicationContext

    private val permissionService = PermissionService(activity)
    private val simInfoService = SimInfoService(appContext)
    private val cellularService = CellularService(appContext, simInfoService)
    private val wifiService = WifiSignalService(appContext)
    private val gnssService = GnssService(appContext)
    private val exportService = ExportService(appContext)
    private val updateInstaller = UpdateInstaller(appContext)

    private val methodChannel = MethodChannel(messenger, METHOD)
    private val cellularChannel = EventChannel(messenger, CELLULAR)
    private val wifiChannel = EventChannel(messenger, WIFI)
    private val wifiScanChannel = EventChannel(messenger, WIFI_SCAN)
    private val gnssChannel = EventChannel(messenger, GNSS)

    fun register() {
        methodChannel.setMethodCallHandler(this)
        cellularChannel.setStreamHandler(stream(
            onStart = { args, sink -> cellularService.start(args, sink) },
            onStop = { cellularService.stop() },
        ))
        wifiChannel.setStreamHandler(stream(
            onStart = { _, sink -> wifiService.startConnectionStream(sink) },
            onStop = { wifiService.stopConnectionStream() },
        ))
        wifiScanChannel.setStreamHandler(stream(
            onStart = { _, sink -> wifiService.startScanStream(sink) },
            onStop = { wifiService.stopScanStream() },
        ))
        gnssChannel.setStreamHandler(stream(
            onStart = { _, sink -> gnssService.start(sink) },
            onStop = { gnssService.stop() },
        ))
    }

    /** Releases every listener. Called when the Flutter engine is torn down. */
    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        cellularChannel.setStreamHandler(null)
        wifiChannel.setStreamHandler(null)
        wifiScanChannel.setStreamHandler(null)
        gnssChannel.setStreamHandler(null)
        cellularService.dispose()
        wifiService.dispose()
        gnssService.dispose()
        simInfoService.dispose()
        permissionService.dispose()
    }

    fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>) {
        permissionService.onRequestPermissionsResult(requestCode, permissions)
    }

    private fun stream(
        onStart: (Any?, EventChannel.EventSink) -> Unit,
        onStop: () -> Unit,
    ) = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            try {
                onStart(arguments, events)
            } catch (e: SecurityException) {
                events.error("permission_denied", e.message, null)
            } catch (t: Throwable) {
                events.error("native_error", t.message, null)
            }
        }

        override fun onCancel(arguments: Any?) {
            try {
                onStop()
            } catch (_: Throwable) {
                // Listener teardown must never crash the app.
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "ping" -> result.success("pong")
                "getCapabilities" -> result.success(capabilities())
                "getPermissions" -> result.success(permissionService.snapshot())
                "requestPermissions" -> {
                    val groups = (call.argument<List<*>>("groups") ?: emptyList<Any>())
                        .filterIsInstance<String>()
                    permissionService.request(groups) { snapshot -> result.success(snapshot) }
                }
                "openAppSettings" -> result.success(
                    startSettings(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                            .setData(Uri.fromParts("package", appContext.packageName, null)),
                    ),
                )
                "openLocationSettings" -> result.success(
                    startSettings(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)),
                )
                "openWifiSettings" -> result.success(
                    startSettings(Intent(Settings.ACTION_WIFI_SETTINGS)),
                )
                "getSimList" -> result.success(simInfoService.getSimList())
                "getWifiConnection" -> result.success(wifiService.getConnection())
                "getWifiScanResults" -> result.success(wifiService.getScanResults())
                "requestWifiScan" -> result.success(wifiService.requestScan())
                "loadSettings" -> result.success(
                    appContext.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
                        .getString(SETTINGS_KEY, null),
                )
                "saveSettings" -> {
                    val json = call.argument<String>("json")
                    appContext.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE)
                        .edit().putString(SETTINGS_KEY, json).apply()
                    result.success(null)
                }
                "saveExport" -> {
                    val name = call.argument<String>("fileName")
                    val mime = call.argument<String>("mimeType") ?: "text/plain"
                    val content = call.argument<String>("content")
                    if (name == null || content == null) {
                        result.error("bad_args", "fileName and content are required", null)
                    } else {
                        result.success(exportService.save(name, mime, content))
                    }
                }
                "getAppBuildInfo" -> result.success(updateInstaller.buildInfo())
                "prepareUpdateDir" -> result.success(updateInstaller.prepareDir())
                "installApk" -> {
                    val path = call.argument<String>("path")
                    val sha256 = call.argument<String>("sha256")
                    if (path == null || sha256 == null) {
                        result.error("bad_args", "path and sha256 are required", null)
                    } else {
                        result.success(updateInstaller.install(path, sha256))
                    }
                }
                "openInstallPermissionSettings" -> result.success(
                    startSettings(
                        Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                            .setData(Uri.fromParts("package", appContext.packageName, null)),
                    ),
                )
                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            result.error("permission_denied", e.message, null)
        } catch (t: Throwable) {
            result.error("native_error", t.message, null)
        }
    }

    private fun startSettings(intent: Intent): Boolean {
        return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun capabilities(): Map<String, Any?> {
        val pm = appContext.packageManager
        val wifi = appContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        val lm = appContext.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        val hasGnss = pm.hasSystemFeature("android.hardware.location.gps") ||
            (lm?.allProviders?.contains(LocationManager.GPS_PROVIDER) == true)
        val wifiEnabled = try {
            wifi?.isWifiEnabled
        } catch (_: SecurityException) {
            null
        }
        return mapOf(
            "platform" to "android",
            "sdkInt" to Build.VERSION.SDK_INT,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "hasTelephony" to pm.hasSystemFeature("android.hardware.telephony"),
            "hasWifi" to pm.hasSystemFeature("android.hardware.wifi"),
            "hasGnss" to hasGnss,
            "wifiEnabled" to wifiEnabled,
            "simCount" to simInfoService.activeSubscriptionCount(),
        )
    }
}
