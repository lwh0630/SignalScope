package com.signalscope.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.NetworkCapabilities
import android.net.wifi.WifiInfo
import android.os.Build
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.NetworkInterface

/**
 * IP addresses and the device MAC, all from public APIs.
 *
 * MAC addresses: since Android 10 apps cannot read the real hardware MAC.
 * `WifiInfo.getMacAddress()` returns the constant `02:00:00:00:00:00` and
 * Android 11+ also hides `NetworkInterface.getHardwareAddress()`. Both are
 * tried and a value is only reported when it is a real, non-placeholder
 * address; otherwise it is null and the UI explains why.
 */
internal object NetworkAddresses {

    private const val PLACEHOLDER_MAC = "02:00:00:00:00:00"

    /** IPv4 / IPv6 addresses of one link. Empty collections mean "none". */
    data class Addresses(
        val ipv4: List<String>,
        val ipv6: List<String>,
        val ipv6LinkLocal: List<String>,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "ipv4" to ipv4.firstOrNull(),
            "ipv6" to ipv6,
            "ipv6LinkLocal" to ipv6LinkLocal,
        )
    }

    val NONE = Addresses(emptyList(), emptyList(), emptyList())

    fun fromLinkProperties(lp: LinkProperties?): Addresses {
        if (lp == null) return NONE
        val v4 = ArrayList<String>()
        val v6 = ArrayList<String>()
        val ll = ArrayList<String>()
        for (la in lp.linkAddresses) {
            val addr = la.address
            when (addr) {
                is Inet4Address -> addr.hostAddress?.let { v4 += it }
                is Inet6Address -> {
                    // Drop the zone suffix (%wlan0) that hostAddress appends to link-local addresses.
                    val text = addr.hostAddress?.substringBefore('%') ?: continue
                    if (addr.isLinkLocalAddress) ll += text else v6 += text
                }
            }
        }
        return Addresses(v4, v6, ll)
    }

    /**
     * Addresses of the mobile-data network that belongs to [subscriptionId].
     *
     * On API 31+ the network's subscription ids identify the SIM. Where the OS
     * does not tell (older versions), only the default data SIM can be
     * assigned a network, so other SIMs are reported as having none rather
     * than guessing.
     */
    @Suppress("DEPRECATION")
    fun cellular(context: Context, subscriptionId: Int, defaultDataSubId: Int?): Addresses? {
        val cm = context.getSystemService(ConnectivityManager::class.java) ?: return null
        val networks = safe { cm.allNetworks } ?: return null
        for (n in networks) {
            val caps = safe { cm.getNetworkCapabilities(n) } ?: continue
            if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) continue
            // IMS / MMS networks are also cellular but are not the data connection.
            if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) continue
            val ids: Set<Int> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                safe { caps.subscriptionIds } ?: emptySet()
            } else emptySet()
            val belongs = if (ids.isNotEmpty()) subscriptionId in ids else subscriptionId == defaultDataSubId
            if (!belongs) continue
            val lp = safe { cm.getLinkProperties(n) } ?: continue
            return fromLinkProperties(lp)
        }
        return null
    }

    /** The Wi-Fi adapter's MAC if (and only if) the OS exposes a real one. */
    @Suppress("DEPRECATION")
    fun wifiMac(info: WifiInfo?): String? {
        val fromInfo = safe { info?.macAddress }
        if (isRealMac(fromInfo)) return fromInfo!!.lowercase()
        val fromInterface = try {
            NetworkInterface.getByName("wlan0")?.hardwareAddress
                ?.joinToString(":") { "%02x".format(it) }
        } catch (_: Exception) {
            null
        }
        return if (isRealMac(fromInterface)) fromInterface else null
    }

    fun isRealMac(mac: String?): Boolean =
        !mac.isNullOrBlank() && mac != PLACEHOLDER_MAC && mac != "00:00:00:00:00:00"
}
