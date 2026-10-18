package com.signalscope.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.telephony.CellIdentityGsm
import android.telephony.CellIdentityLte
import android.telephony.CellIdentityNr
import android.telephony.CellIdentityTdscdma
import android.telephony.CellIdentityWcdma
import android.telephony.CellInfo
import android.telephony.CellInfoCdma
import android.telephony.CellInfoGsm
import android.telephony.CellInfoLte
import android.telephony.CellInfoNr
import android.telephony.CellInfoTdscdma
import android.telephony.CellInfoWcdma
import android.telephony.CellSignalStrength
import android.telephony.CellSignalStrengthCdma
import android.telephony.CellSignalStrengthGsm
import android.telephony.CellSignalStrengthLte
import android.telephony.CellSignalStrengthNr
import android.telephony.CellSignalStrengthTdscdma
import android.telephony.CellSignalStrengthWcdma
import android.telephony.PhoneStateListener
import android.telephony.ServiceState
import android.telephony.SignalStrength
import android.telephony.SubscriptionManager
import android.telephony.TelephonyCallback
import android.telephony.TelephonyDisplayInfo
import android.telephony.TelephonyManager
import io.flutter.plugin.common.EventChannel

/**
 * Event-driven cellular monitor.
 *
 * For every requested subscription id a [SubMonitor] registers:
 *  * Android 12+ (API 31): one [TelephonyCallback] per listener type
 *    (signal strength, service state, display info, cell info).
 *  * Android 10-11 (API 29-30): a [PhoneStateListener].
 *
 * Cell identities come from `TelephonyManager.requestCellInfoUpdate`
 * (API 29+), requested at most every [MIN_CELL_REQUEST_INTERVAL_MS] and only
 * as a reaction to a system callback - there is no polling timer.
 *
 * Only public APIs are used; every value the OS does not report is sent as
 * null.
 */
class CellularService(
    private val context: Context,
    private val simInfoService: SimInfoService,
) {

    companion object {
        private const val EMIT_COALESCE_MS = 200L
        private const val MIN_CELL_REQUEST_INTERVAL_MS = 3000L
    }

    private val handler = Handler(Looper.getMainLooper())
    private val executor = context.mainExecutor

    private var sink: EventChannel.EventSink? = null
    private val monitors = LinkedHashMap<Int, SubMonitor>()

    private var subscriptionsListener: SubscriptionManager.OnSubscriptionsChangedListener? = null
    private var knownSubscriptionIds: Set<Int> = emptySet()
    private var firstSubscriptionCallback = true

    fun start(arguments: Any?, sink: EventChannel.EventSink) {
        stop()
        this.sink = sink

        val requested = ((arguments as? Map<*, *>)?.get("subscriptionIds") as? List<*>)
            ?.filterIsInstance<Number>()
            ?.map { it.toInt() }
            ?: emptyList()

        for (subId in requested.distinct()) {
            val monitor = SubMonitor(subId)
            monitors[subId] = monitor
            monitor.start()
        }
        registerSubscriptionsListener()
        registerNetworkCallback()
    }

    fun stop() {
        monitors.values.forEach { it.stop() }
        monitors.clear()
        unregisterSubscriptionsListener()
        unregisterNetworkCallback()
        handler.removeCallbacksAndMessages(null)
        sink = null
    }

    fun dispose() {
        stop()
    }

    // ---- mobile-data network changes (IP address assigned / lost) ----

    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    private fun registerNetworkCallback() {
        val cm = context.getSystemService(ConnectivityManager::class.java) ?: return
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = notifyNetworkChanged()
            override fun onLost(network: Network) = notifyNetworkChanged()
            override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) =
                notifyNetworkChanged()
            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) =
                notifyNetworkChanged()
        }
        try {
            cm.registerNetworkCallback(
                NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .build(),
                callback,
                handler,
            )
            networkCallback = callback
        } catch (_: SecurityException) {
            // Addresses then only refresh together with the next telephony callback.
        } catch (_: RuntimeException) {
        }
    }

    private fun unregisterNetworkCallback() {
        val cb = networkCallback ?: return
        networkCallback = null
        try {
            context.getSystemService(ConnectivityManager::class.java)?.unregisterNetworkCallback(cb)
        } catch (_: RuntimeException) {
        }
    }

    private fun notifyNetworkChanged() {
        monitors.values.forEach { it.onNetworkChanged() }
    }

    // ---- subscription changes (SIM inserted / removed) ----

    private fun registerSubscriptionsListener() {
        if (!Perms.hasPhoneState(context)) return
        val sm = context.getSystemService(SubscriptionManager::class.java) ?: return
        knownSubscriptionIds = simInfoService.activeSubscriptions().map { it.subscriptionId }.toSet()
        firstSubscriptionCallback = true
        val listener = object : SubscriptionManager.OnSubscriptionsChangedListener() {
            override fun onSubscriptionsChanged() {
                // The system invokes this once right after registration; ignore that call.
                if (firstSubscriptionCallback) {
                    firstSubscriptionCallback = false
                    return
                }
                val now = simInfoService.activeSubscriptions().map { it.subscriptionId }.toSet()
                if (now != knownSubscriptionIds) {
                    knownSubscriptionIds = now
                    sink?.success(mapOf("type" to "simsChanged"))
                }
            }
        }
        try {
            sm.addOnSubscriptionsChangedListener(executor, listener)
            subscriptionsListener = listener
        } catch (_: SecurityException) {
            // Without the permission we simply do not get SIM change events.
        }
    }

    private fun unregisterSubscriptionsListener() {
        val l = subscriptionsListener ?: return
        subscriptionsListener = null
        try {
            context.getSystemService(SubscriptionManager::class.java)
                ?.removeOnSubscriptionsChangedListener(l)
        } catch (_: RuntimeException) {
        }
    }

    // ---- per-subscription monitor ----

    private inner class SubMonitor(private val subId: Int) {
        private val tm: TelephonyManager? = simInfoService.telephonyFor(subId)

        private var lastSignal: SignalStrength? = null
        private var lastService: ServiceState? = null
        private var lastCells: List<CellInfo>? = null
        private var overrideNetworkType: Int? = null

        private val callbacks: MutableList<Any> = mutableListOf()
        private var legacyListener: PhoneStateListener? = null

        private var emitScheduled = false
        private var cellRequestInFlight = false
        private var lastCellRequestAt = 0L
        private var active = false
        private val issues = mutableListOf<String>()

        private val emitRunnable = Runnable {
            emitScheduled = false
            if (active) emitNow()
        }

        /** The data network (and its IP addresses) changed. */
        fun onNetworkChanged() {
            if (active) scheduleEmit()
        }

        fun start() {
            val tm = tm
            if (tm == null) {
                issues += "telephony_unavailable"
                emitNow()
                return
            }
            active = true

            if (!Perms.hasPhoneState(context)) {
                issues += "no_phone_permission"
            } else {
                // Seed with whatever the system already holds so the UI is not empty.
                lastSignal = safe { tm.signalStrength }
                lastService = safe { tm.serviceState }
                if (Perms.hasFineLocation(context)) {
                    lastCells = safe { tm.allCellInfo }?.takeIf { it.isNotEmpty() }
                }
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) registerCallbacks(tm)
                    else registerLegacyListener(tm)
                } catch (e: SecurityException) {
                    issues += "no_phone_permission"
                } catch (e: RuntimeException) {
                    issues += "listener_failed"
                }
            }
            if (!Perms.hasFineLocation(context)) issues += "no_location_permission"

            requestCellInfo(force = true)
            emitNow()
        }

        @Suppress("DEPRECATION")
        fun stop() {
            active = false
            handler.removeCallbacks(emitRunnable)
            emitScheduled = false
            val tm = tm
            if (tm != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    for (cb in callbacks) {
                        try {
                            tm.unregisterTelephonyCallback(cb as TelephonyCallback)
                        } catch (_: RuntimeException) {
                        }
                    }
                }
                legacyListener?.let {
                    try {
                        tm.listen(it, PhoneStateListener.LISTEN_NONE)
                    } catch (_: RuntimeException) {
                    }
                }
            }
            callbacks.clear()
            legacyListener = null
            lastSignal = null
            lastService = null
            lastCells = null
        }

        // ---- API 31+ ----
        private fun registerCallbacks(tm: TelephonyManager) {
            val fine = Perms.hasFineLocation(context)
            val list = mutableListOf<TelephonyCallback>()
            list += SignalCb()
            list += ServiceCb()
            list += DisplayCb()
            if (fine) list += CellInfoCb()
            for (cb in list) {
                try {
                    tm.registerTelephonyCallback(executor, cb)
                    callbacks += cb
                } catch (e: SecurityException) {
                    issues += "callback_denied"
                }
            }
        }

        private inner class SignalCb : TelephonyCallback(), TelephonyCallback.SignalStrengthsListener {
            override fun onSignalStrengthsChanged(signalStrength: SignalStrength) {
                onSignal(signalStrength)
            }
        }

        private inner class ServiceCb : TelephonyCallback(), TelephonyCallback.ServiceStateListener {
            override fun onServiceStateChanged(serviceState: ServiceState) {
                onService(serviceState)
            }
        }

        private inner class DisplayCb : TelephonyCallback(), TelephonyCallback.DisplayInfoListener {
            override fun onDisplayInfoChanged(telephonyDisplayInfo: TelephonyDisplayInfo) {
                onDisplay(telephonyDisplayInfo)
            }
        }

        private inner class CellInfoCb : TelephonyCallback(), TelephonyCallback.CellInfoListener {
            override fun onCellInfoChanged(cellInfo: MutableList<CellInfo>) {
                onCells(cellInfo)
            }
        }

        // ---- API 29-30 ----
        @Suppress("DEPRECATION")
        private fun registerLegacyListener(tm: TelephonyManager) {
            var events = PhoneStateListener.LISTEN_SIGNAL_STRENGTHS or PhoneStateListener.LISTEN_SERVICE_STATE
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                events = events or PhoneStateListener.LISTEN_DISPLAY_INFO_CHANGED
            }
            if (Perms.hasFineLocation(context)) {
                events = events or PhoneStateListener.LISTEN_CELL_INFO
            }
            val listener = object : PhoneStateListener() {
                override fun onSignalStrengthsChanged(signalStrength: SignalStrength) {
                    onSignal(signalStrength)
                }

                override fun onServiceStateChanged(serviceState: ServiceState?) {
                    if (serviceState != null) onService(serviceState)
                }

                override fun onCellInfoChanged(cellInfo: MutableList<CellInfo>?) {
                    if (cellInfo != null) onCells(cellInfo)
                }

                override fun onDisplayInfoChanged(telephonyDisplayInfo: TelephonyDisplayInfo) {
                    onDisplay(telephonyDisplayInfo)
                }
            }
            tm.listen(listener, events)
            legacyListener = listener
        }

        // ---- event handlers ----
        private fun onSignal(s: SignalStrength) {
            lastSignal = s
            requestCellInfo(force = false)
            scheduleEmit()
        }

        private fun onService(s: ServiceState) {
            lastService = s
            requestCellInfo(force = false)
            scheduleEmit()
        }

        private fun onDisplay(info: TelephonyDisplayInfo) {
            overrideNetworkType = info.overrideNetworkType
            scheduleEmit()
        }

        private fun onCells(cells: List<CellInfo>) {
            lastCells = cells
            scheduleEmit()
        }

        /** Asks the OS for fresh cell info, rate limited; reacts to callbacks only. */
        private fun requestCellInfo(force: Boolean) {
            val tm = tm ?: return
            if (!active || cellRequestInFlight) return
            if (!Perms.hasFineLocation(context) || !Perms.hasPhoneState(context)) return
            val now = SystemClock.elapsedRealtime()
            if (!force && now - lastCellRequestAt < MIN_CELL_REQUEST_INTERVAL_MS) return
            lastCellRequestAt = now
            cellRequestInFlight = true
            try {
                tm.requestCellInfoUpdate(executor, object : TelephonyManager.CellInfoCallback() {
                    override fun onCellInfo(cellInfo: MutableList<CellInfo>) {
                        cellRequestInFlight = false
                        if (!active) return
                        lastCells = cellInfo
                        scheduleEmit()
                    }

                    override fun onError(errorCode: Int, detail: Throwable?) {
                        cellRequestInFlight = false
                    }
                })
            } catch (_: SecurityException) {
                cellRequestInFlight = false
            } catch (_: RuntimeException) {
                cellRequestInFlight = false
            }
        }

        private fun scheduleEmit() {
            if (!active || emitScheduled) return
            emitScheduled = true
            handler.postDelayed(emitRunnable, EMIT_COALESCE_MS)
        }

        private fun emitNow() {
            val s = sink ?: return
            s.success(buildSnapshot())
        }

        // ---- snapshot ----
        private fun buildSnapshot(): Map<String, Any?> {
            val tm = tm
            val strengths: List<CellSignalStrength> = lastSignal?.cellSignalStrengths ?: emptyList()
            val cells = lastCells ?: emptyList()

            val lte = ArrayList<Map<String, Any?>>()
            val nr = ArrayList<Map<String, Any?>>()
            val legacy = ArrayList<Map<String, Any?>>()

            for (c in cells) {
                when (c) {
                    is CellInfoLte -> lte += lteFromCellInfo(c)
                    is CellInfoNr -> nrFromCellInfo(c)?.let { nr += it }
                    is CellInfoGsm -> legacy += gsmFromCellInfo(c)
                    is CellInfoWcdma -> legacy += wcdmaFromCellInfo(c)
                    is CellInfoTdscdma -> legacy += tdscdmaFromCellInfo(c)
                    is CellInfoCdma -> legacy += cdmaFromCellInfo(c)
                    else -> {}
                }
            }

            // Measurements from SignalStrength are added only for RATs for which no
            // registered CellInfo entry exists (e.g. NSA NR, or no location permission).
            // They are tagged source=signalStrength and carry no cell identity.
            fun hasRegistered(list: List<Map<String, Any?>>) = list.any { it["isRegistered"] == true }
            for (s in strengths) {
                when (s) {
                    is CellSignalStrengthLte -> if (!hasRegistered(lte)) lteFromStrength(s)?.let { lte += it }
                    is CellSignalStrengthNr -> if (!hasRegistered(nr)) nrFromStrength(s)?.let { nr += it }
                    is CellSignalStrengthGsm -> if (!hasRegistered(legacy.filter { it["rat"] == "GSM" })) legacy += legacyFromStrength("GSM", s)
                    is CellSignalStrengthWcdma -> if (!hasRegistered(legacy.filter { it["rat"] == "WCDMA" })) legacy += legacyFromStrength("WCDMA", s)
                    is CellSignalStrengthTdscdma -> if (!hasRegistered(legacy.filter { it["rat"] == "TDSCDMA" })) legacy += legacyFromStrength("TDSCDMA", s)
                    is CellSignalStrengthCdma -> if (!hasRegistered(legacy.filter { it["rat"] == "CDMA" })) legacy += legacyFromStrength("CDMA", s)
                    else -> {}
                }
            }

            val primary = strengths.firstOrNull()
            val snapshotIssues = LinkedHashSet<String>(issues)
            if (!Perms.hasFineLocation(context)) snapshotIssues += "no_location_permission"
            if (Perms.hasFineLocation(context) && cells.isEmpty()) snapshotIssues += "cell_info_empty"

            val state = lastService ?: safe { tm?.serviceState }
            val defaultData = safe { SubscriptionManager.getDefaultDataSubscriptionId() }
                ?.takeIf { it != SubscriptionManager.INVALID_SUBSCRIPTION_ID }
            val addresses = NetworkAddresses.cellular(context, subId, defaultData)
            return mapOf(
                "type" to "snapshot",
                "subscriptionId" to subId,
                "timestampMs" to System.currentTimeMillis(),
                "signalLevel" to lastSignal?.level,
                "serviceState" to state?.state,
                "operatorName" to safe { tm?.networkOperatorName }.nullIfBlank(),
                "networkOperator" to safe { tm?.networkOperator }.nullIfBlank(),
                "isRoaming" to safe { tm?.isNetworkRoaming },
                "dataNetworkType" to safe { tm?.dataNetworkType },
                "voiceNetworkType" to safe { tm?.voiceNetworkType },
                // null addresses: this SIM currently has no mobile-data network.
                "hasDataNetwork" to (addresses != null),
                "ipv4" to addresses?.ipv4?.firstOrNull(),
                "ipv6" to (addresses?.ipv6 ?: emptyList<String>()),
                "ipv6LinkLocal" to (addresses?.ipv6LinkLocal ?: emptyList<String>()),
                "overrideNetworkType" to overrideNetworkType,
                "primaryRat" to primary?.let { ratOf(it) },
                "primaryDbm" to primary?.dbm?.validOrNull(),
                "lte" to lte,
                "nr" to nr,
                "legacy" to legacy,
                "cellInfoAvailable" to cells.isNotEmpty(),
                "issues" to snapshotIssues.toList(),
            )
        }
    }

    // ---- mapping helpers (pure functions of system objects) ----

    private fun ratOf(s: CellSignalStrength): String? = when (s) {
        is CellSignalStrengthNr -> "NR"
        is CellSignalStrengthLte -> "LTE"
        is CellSignalStrengthWcdma -> "WCDMA"
        is CellSignalStrengthGsm -> "GSM"
        is CellSignalStrengthTdscdma -> "TDSCDMA"
        is CellSignalStrengthCdma -> "CDMA"
        else -> null
    }

    private fun lteMeasurements(s: CellSignalStrengthLte): Map<String, Any?> = mapOf(
        "rsrp" to s.rsrp.validOrNull(),
        "rsrq" to s.rsrq.validOrNull(),
        "rssi" to s.rssi.validOrNull(),
        "rssnr" to s.rssnr.validOrNull(),
        "cqi" to s.cqi.validOrNull(),
        "timingAdvance" to s.timingAdvance.validOrNull(),
        "level" to s.level,
        "dbm" to s.dbm.validOrNull(),
    )

    private fun lteFromCellInfo(c: CellInfoLte): Map<String, Any?> {
        val id: CellIdentityLte = c.cellIdentity
        val bands = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) id.bands.toList() else emptyList()
        return mapOf(
            "isRegistered" to c.isRegistered,
            "source" to "cellInfo",
            "pci" to id.pci.validOrNull(),
            "tac" to id.tac.validOrNull(),
            "ci" to id.ci.validOrNull(),
            "earfcn" to id.earfcn.validOrNull(),
            "bandwidthKhz" to id.bandwidth.validOrNull(),
            "bands" to bands,
            "mcc" to id.mccString,
            "mnc" to id.mncString,
        ) + lteMeasurements(c.cellSignalStrength)
    }

    private fun lteFromStrength(s: CellSignalStrengthLte): Map<String, Any?>? {
        val m = lteMeasurements(s)
        if (m["rsrp"] == null && m["rsrq"] == null && m["rssi"] == null && m["rssnr"] == null && m["dbm"] == null) return null
        return mapOf("isRegistered" to null, "source" to "signalStrength") + m
    }

    private fun nrMeasurements(s: CellSignalStrengthNr): Map<String, Any?> = mapOf(
        "ssRsrp" to s.ssRsrp.validOrNull(),
        "ssRsrq" to s.ssRsrq.validOrNull(),
        "ssSinr" to s.ssSinr.validOrNull(),
        "csiRsrp" to s.csiRsrp.validOrNull(),
        "csiRsrq" to s.csiRsrq.validOrNull(),
        "csiSinr" to s.csiSinr.validOrNull(),
        "level" to s.level,
        "dbm" to s.dbm.validOrNull(),
    )

    private fun nrFromCellInfo(c: CellInfoNr): Map<String, Any?>? {
        val id = c.cellIdentity as? CellIdentityNr ?: return null
        val ss = c.cellSignalStrength as? CellSignalStrengthNr
        val measurements = if (ss != null) nrMeasurements(ss) else emptyMap()
        return mapOf(
            "isRegistered" to c.isRegistered,
            "source" to "cellInfo",
            "nrarfcn" to id.nrarfcn.validOrNull(),
            "pci" to id.pci.validOrNull(),
            "tac" to id.tac.validOrNull(),
            "nci" to id.nci.validOrNull(),
            "bands" to id.bands.toList(),
            "mcc" to id.mccString,
            "mnc" to id.mncString,
        ) + measurements
    }

    private fun nrFromStrength(s: CellSignalStrengthNr): Map<String, Any?>? {
        val m = nrMeasurements(s)
        val hasAny = listOf("ssRsrp", "ssRsrq", "ssSinr", "csiRsrp", "csiRsrq", "csiSinr", "dbm").any { m[it] != null }
        if (!hasAny) return null
        return mapOf("isRegistered" to null, "source" to "signalStrength") + m
    }

    private fun gsmFromCellInfo(c: CellInfoGsm): Map<String, Any?> {
        val id: CellIdentityGsm = c.cellIdentity
        return mapOf(
            "rat" to "GSM",
            "isRegistered" to c.isRegistered,
            "source" to "cellInfo",
            "dbm" to c.cellSignalStrength.dbm.validOrNull(),
            "level" to c.cellSignalStrength.level,
            "cid" to id.cid.validOrNull(),
            "lac" to id.lac.validOrNull(),
            "channel" to id.arfcn.validOrNull(),
            "bsic" to id.bsic.validOrNull(),
            "mcc" to id.mccString,
            "mnc" to id.mncString,
        )
    }

    private fun wcdmaFromCellInfo(c: CellInfoWcdma): Map<String, Any?> {
        val id: CellIdentityWcdma = c.cellIdentity
        return mapOf(
            "rat" to "WCDMA",
            "isRegistered" to c.isRegistered,
            "source" to "cellInfo",
            "dbm" to c.cellSignalStrength.dbm.validOrNull(),
            "level" to c.cellSignalStrength.level,
            "cid" to id.cid.validOrNull(),
            "lac" to id.lac.validOrNull(),
            "channel" to id.uarfcn.validOrNull(),
            "psc" to id.psc.validOrNull(),
            "mcc" to id.mccString,
            "mnc" to id.mncString,
        )
    }

    private fun tdscdmaFromCellInfo(c: CellInfoTdscdma): Map<String, Any?> {
        val id: CellIdentityTdscdma = c.cellIdentity
        return mapOf(
            "rat" to "TDSCDMA",
            "isRegistered" to c.isRegistered,
            "source" to "cellInfo",
            "dbm" to c.cellSignalStrength.dbm.validOrNull(),
            "level" to c.cellSignalStrength.level,
            "cid" to id.cid.validOrNull(),
            "lac" to id.lac.validOrNull(),
            "channel" to id.uarfcn.validOrNull(),
            "mcc" to id.mccString,
            "mnc" to id.mncString,
        )
    }

    private fun cdmaFromCellInfo(c: CellInfoCdma): Map<String, Any?> = mapOf(
        "rat" to "CDMA",
        "isRegistered" to c.isRegistered,
        "source" to "cellInfo",
        "dbm" to c.cellSignalStrength.dbm.validOrNull(),
        "level" to c.cellSignalStrength.level,
        "cid" to c.cellIdentity.basestationId.validOrNull(),
    )

    private fun legacyFromStrength(rat: String, s: CellSignalStrength): Map<String, Any?> = mapOf(
        "rat" to rat,
        "isRegistered" to null,
        "source" to "signalStrength",
        "dbm" to s.dbm.validOrNull(),
        "level" to s.level,
    )
}
