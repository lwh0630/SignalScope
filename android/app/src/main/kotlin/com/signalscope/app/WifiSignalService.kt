package com.signalscope.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.ScanResult
import android.net.wifi.SupplicantState
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.EventChannel
import java.net.Inet4Address

/**
 * Wi-Fi connection details, cached scan results and change listeners.
 *
 * Scanning rules:
 *  * Real-time updates are event driven: `RSSI_CHANGED_ACTION`, a Wi-Fi
 *    `NetworkCallback` and `SCAN_RESULTS_AVAILABLE_ACTION`.
 *  * Reading results never starts a scan.
 *  * An explicit scan request is only forwarded to `WifiManager.startScan()`
 *    while we stay under the Android foreground limit of 4 scans / 2 minutes.
 */
class WifiSignalService(private val context: Context) {

    companion object {
        private const val EMIT_COALESCE_MS = 300L
        private const val SCAN_WINDOW_MS = 120_000L
        private const val MAX_SCANS_PER_WINDOW = 4
        private const val UNKNOWN_BSSID = "02:00:00:00:00:00"

        /** Sentinel documented for `WifiInfo.getRssi()` when no RSSI is available. */
        private const val INVALID_RSSI = -127
    }

    private val wifiManager: WifiManager? =
        context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
    private val connectivityManager: ConnectivityManager? =
        context.getSystemService(ConnectivityManager::class.java)
    private val handler = Handler(Looper.getMainLooper())

    private val scanTimes = ArrayDeque<Long>()

    // connection stream
    private var connSink: EventChannel.EventSink? = null
    private var connReceiver: BroadcastReceiver? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var connEmitScheduled = false
    private val connEmit = Runnable {
        connEmitScheduled = false
        connSink?.success(buildConnection())
    }

    // scan stream
    private var scanSink: EventChannel.EventSink? = null
    private var scanReceiver: BroadcastReceiver? = null

    // ---- one-shot queries ----

    fun getConnection(): Map<String, Any?> = buildConnection()

    fun getScanResults(): Map<String, Any?> = buildScan(started = null, throttled = false, retryAfterMs = null)

    /**
     * Asks the OS to start a scan. Never exceeds 4 requests per 2 minutes; if the budget
     * is used up the request is not forwarded and `retryAfterMs` tells when to try again.
     */
    fun requestScan(): Map<String, Any?> {
        val wm = wifiManager ?: return buildScan(null, false, null)
        val now = SystemClock.elapsedRealtime()
        while (scanTimes.isNotEmpty() && now - scanTimes.first() > SCAN_WINDOW_MS) scanTimes.removeFirst()
        if (scanTimes.size >= MAX_SCANS_PER_WINDOW) {
            val retry = SCAN_WINDOW_MS - (now - scanTimes.first())
            return buildScan(started = false, throttled = true, retryAfterMs = retry)
        }
        @Suppress("DEPRECATION")
        val accepted = safe { wm.startScan() } ?: false
        if (accepted) {
            scanTimes.addLast(now)
        }
        // If the OS refused, it is applying its own throttling.
        return buildScan(started = accepted, throttled = !accepted, retryAfterMs = null)
    }

    // ---- connection snapshot ----

    private fun hasLocationAccess(): Boolean = Perms.hasFineLocation(context)

    private fun cleanSsid(raw: String?): String? {
        if (raw.isNullOrEmpty() || raw == WifiManager.UNKNOWN_SSID) return null
        return if (raw.length >= 2 && raw.startsWith("\"") && raw.endsWith("\"")) {
            raw.substring(1, raw.length - 1).nullIfBlank()
        } else {
            raw
        }
    }

    @Suppress("DEPRECATION")
    private fun buildConnection(): Map<String, Any?> {
        val now = System.currentTimeMillis()
        val wm = wifiManager
            ?: return mapOf(
                "timestampMs" to now,
                "wifiEnabled" to null,
                "connected" to false,
                "issues" to listOf("wifi_unsupported"),
            )
        val issues = LinkedHashSet<String>()
        val enabled = safe { wm.isWifiEnabled }
        if (enabled == false) {
            issues += "wifi_disabled"
            return mapOf(
                "timestampMs" to now,
                "wifiEnabled" to false,
                "connected" to false,
                "issues" to issues.toList(),
            )
        }
        if (!hasLocationAccess()) issues += "no_location_permission"
        if (Perms.isLocationEnabled(context) == false) issues += "location_off"

        val info: WifiInfo? = safe { wm.connectionInfo }
        val connected = info != null &&
            (info.supplicantState == SupplicantState.COMPLETED || info.networkId != -1) &&
            info.rssi > INVALID_RSSI
        if (!connected || info == null) {
            return mapOf(
                "timestampMs" to now,
                "wifiEnabled" to enabled,
                "connected" to false,
                "issues" to issues.toList(),
            )
        }

        val ssid = cleanSsid(info.ssid)
        val bssid = info.bssid?.takeIf { it != UNKNOWN_BSSID }
        if (ssid == null && hasLocationAccess() && Perms.isLocationEnabled(context) != false) {
            // Permission is fine but the OS still hides the name (hidden SSID or OS policy).
            issues += "ssid_hidden"
        }

        // Match with the scan cache for channel width / capabilities.
        val match: ScanResult? = if (bssid != null) {
            safe { wm.scanResults }?.firstOrNull { it.BSSID.equals(bssid, ignoreCase = true) }
        } else null

        val net = findWifiNetwork()
        val lp: LinkProperties? = net?.let { safe { connectivityManager?.getLinkProperties(it) } }
        val addresses = NetworkAddresses.fromLinkProperties(lp)
        val ipv4 = addresses.ipv4.firstOrNull()
        val gateway = lp?.routes
            ?.firstOrNull { it.isDefaultRoute && it.gateway is Inet4Address }
            ?.gateway?.hostAddress
        val dns = lp?.dnsServers?.mapNotNull { it.hostAddress } ?: emptyList()

        val standard = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            info.wifiStandard.takeIf { it > 0 } ?: match?.wifiStandard?.takeIf { it > 0 }
        } else null
        val security = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            info.currentSecurityType.takeIf { it >= 0 }
        } else null

        return mapOf(
            "timestampMs" to now,
            "wifiEnabled" to enabled,
            "connected" to true,
            "ssid" to ssid,
            "bssid" to bssid,
            "rssi" to info.rssi,
            "frequencyMhz" to info.frequency.takeIf { it > 0 },
            "linkSpeedMbps" to info.linkSpeed.takeIf { it > 0 },
            "txLinkSpeedMbps" to info.txLinkSpeedMbps.takeIf { it > 0 },
            "rxLinkSpeedMbps" to info.rxLinkSpeedMbps.takeIf { it > 0 },
            "ipAddress" to ipv4,
            "ipv6" to addresses.ipv6,
            "ipv6LinkLocal" to addresses.ipv6LinkLocal,
            "macAddress" to NetworkAddresses.wifiMac(info),
            "gateway" to gateway,
            "dns" to dns,
            "securityType" to security,
            "capabilities" to match?.capabilities,
            "wifiStandard" to standard,
            "channelWidthCode" to match?.channelWidth,
            "issues" to issues.toList(),
        )
    }

    @Suppress("DEPRECATION")
    private fun findWifiNetwork(): Network? {
        val cm = connectivityManager ?: return null
        val networks = safe { cm.allNetworks } ?: return null
        return networks.firstOrNull { n ->
            safe { cm.getNetworkCapabilities(n)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) } == true
        }
    }

    // ---- scan snapshot ----

    @Suppress("DEPRECATION")
    private fun buildScan(started: Boolean?, throttled: Boolean, retryAfterMs: Long?): Map<String, Any?> {
        val wm = wifiManager
        val issues = LinkedHashSet<String>()
        val results = ArrayList<Map<String, Any?>>()
        if (wm == null) {
            issues += "wifi_unsupported"
        } else {
            val enabled = safe { wm.isWifiEnabled }
            if (enabled == false) issues += "wifi_disabled"
            val permitted = hasLocationAccess() || Perms.hasNearbyWifi(context)
            if (!permitted) issues += "no_location_permission"
            if (Perms.isLocationEnabled(context) == false) issues += "location_off"
            if (permitted) {
                val list: List<ScanResult>? = safe { wm.scanResults }
                list?.forEach { results += describe(it) }
            }
        }
        return mapOf(
            "timestampMs" to System.currentTimeMillis(),
            "results" to results,
            "scanStarted" to started,
            "throttled" to throttled,
            "retryAfterMs" to retryAfterMs,
            "issues" to issues.toList(),
        )
    }

    @Suppress("DEPRECATION")
    private fun describe(r: ScanResult): Map<String, Any?> = mapOf(
        "ssid" to r.SSID.nullIfBlank(),
        "bssid" to r.BSSID,
        "rssi" to r.level,
        "frequencyMhz" to r.frequency,
        "centerFreq0Mhz" to r.centerFreq0.takeIf { it > 0 },
        "centerFreq1Mhz" to r.centerFreq1.takeIf { it > 0 },
        "channelWidthCode" to r.channelWidth,
        "capabilities" to r.capabilities.nullIfBlank(),
        "wifiStandard" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) r.wifiStandard.takeIf { it > 0 } else null,
        "timestampUs" to r.timestamp,
    )

    // ---- connection stream ----

    fun startConnectionStream(sink: EventChannel.EventSink) {
        stopConnectionStream()
        connSink = sink

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, intent: Intent?) {
                scheduleConnEmit()
            }
        }
        val filter = IntentFilter().apply {
            addAction(WifiManager.RSSI_CHANGED_ACTION)
            addAction(WifiManager.WIFI_STATE_CHANGED_ACTION)
            @Suppress("DEPRECATION")
            addAction(WifiManager.NETWORK_STATE_CHANGED_ACTION)
        }
        registerReceiverCompat(receiver, filter)
        connReceiver = receiver

        val cm = connectivityManager
        if (cm != null) {
            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) = scheduleConnEmit()
                override fun onLinkPropertiesChanged(network: Network, lp: LinkProperties) = scheduleConnEmit()
                override fun onAvailable(network: Network) = scheduleConnEmit()
                override fun onLost(network: Network) = scheduleConnEmit()
            }
            try {
                cm.registerNetworkCallback(
                    NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI).build(),
                    callback,
                    handler,
                )
                networkCallback = callback
            } catch (_: SecurityException) {
                // Optional: we still have the broadcasts.
            } catch (_: RuntimeException) {
            }
        }
        sink.success(buildConnection())
    }

    fun stopConnectionStream() {
        handler.removeCallbacks(connEmit)
        connEmitScheduled = false
        connReceiver?.let { unregisterReceiverQuietly(it) }
        connReceiver = null
        networkCallback?.let {
            try {
                connectivityManager?.unregisterNetworkCallback(it)
            } catch (_: RuntimeException) {
            }
        }
        networkCallback = null
        connSink = null
    }

    private fun scheduleConnEmit() {
        if (connSink == null || connEmitScheduled) return
        connEmitScheduled = true
        handler.postDelayed(connEmit, EMIT_COALESCE_MS)
    }

    // ---- scan results stream ----

    fun startScanStream(sink: EventChannel.EventSink) {
        stopScanStream()
        scanSink = sink
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, intent: Intent?) {
                // Reads the cache only; never triggers a scan.
                scanSink?.success(buildScan(null, false, null))
            }
        }
        registerReceiverCompat(receiver, IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION))
        scanReceiver = receiver
        sink.success(buildScan(null, false, null))
    }

    fun stopScanStream() {
        scanReceiver?.let { unregisterReceiverQuietly(it) }
        scanReceiver = null
        scanSink = null
    }

    // ---- helpers ----

    private fun registerReceiverCompat(receiver: BroadcastReceiver, filter: IntentFilter) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
    }

    private fun unregisterReceiverQuietly(receiver: BroadcastReceiver) {
        try {
            context.unregisterReceiver(receiver)
        } catch (_: IllegalArgumentException) {
        }
    }

    fun dispose() {
        stopConnectionStream()
        stopScanStream()
    }
}
