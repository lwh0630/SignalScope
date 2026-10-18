package com.signalscope.app

import android.content.Context
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager

/**
 * One-shot SIM / subscription queries built only on public APIs
 * (SubscriptionManager, TelephonyManager). Every field is nullable: when the
 * system does not report something we send null, never a made-up value.
 */
class SimInfoService(private val context: Context) {

    private val subscriptionManager: SubscriptionManager? =
        context.getSystemService(SubscriptionManager::class.java)
    private val telephonyManager: TelephonyManager? =
        context.getSystemService(TelephonyManager::class.java)

    /** Active subscriptions; empty without READ_PHONE_STATE or without an active SIM. */
    fun activeSubscriptions(): List<SubscriptionInfo> {
        if (!Perms.hasPhoneState(context)) return emptyList()
        return safe { subscriptionManager?.activeSubscriptionInfoList } ?: emptyList()
    }

    /** Number of active subscriptions, or null when it cannot be read. */
    fun activeSubscriptionCount(): Int? {
        if (!Perms.hasPhoneState(context)) return null
        return safe { subscriptionManager?.activeSubscriptionInfoList?.size }
    }

    fun telephonyFor(subscriptionId: Int): TelephonyManager? =
        safe { telephonyManager?.createForSubscriptionId(subscriptionId) }

    fun getSimList(): List<Map<String, Any?>> {
        val defaultData = safe { SubscriptionManager.getDefaultDataSubscriptionId() }
        return activeSubscriptions()
            .sortedBy { it.simSlotIndex }
            .map { describe(it, defaultData) }
    }

    private fun describe(info: SubscriptionInfo, defaultDataSubId: Int?): Map<String, Any?> {
        val subId = info.subscriptionId
        val slot = info.simSlotIndex.takeIf { it >= 0 }
        val tm = telephonyFor(subId)

        val simState = safe {
            if (slot != null) telephonyManager?.getSimState(slot) else tm?.simState
        }

        return mapOf(
            "subscriptionId" to subId,
            "slotIndex" to slot,
            "displayName" to info.displayName?.toString().nullIfBlank(),
            "carrierName" to info.carrierName?.toString().nullIfBlank(),
            "mcc" to info.mccString.nullIfBlank(),
            "mnc" to info.mncString.nullIfBlank(),
            "countryIso" to info.countryIso.nullIfBlank(),
            "isEmbedded" to safe { info.isEmbedded },
            "simState" to simState,
            "simOperator" to safe { tm?.simOperator }.nullIfBlank(),
            "simOperatorName" to safe { tm?.simOperatorName }.nullIfBlank(),
            "networkOperator" to safe { tm?.networkOperator }.nullIfBlank(),
            "networkOperatorName" to safe { tm?.networkOperatorName }.nullIfBlank(),
            "networkCountryIso" to safe { tm?.networkCountryIso }.nullIfBlank(),
            "isRoaming" to safe { tm?.isNetworkRoaming },
            "isDefaultData" to (defaultDataSubId != null && defaultDataSubId == subId),
            "isDataEnabled" to safe { tm?.isDataEnabled },
            "dataState" to safe { tm?.dataState },
            "dataNetworkType" to safe { tm?.dataNetworkType },
            "voiceNetworkType" to safe { tm?.voiceNetworkType },
        )
    }

    fun dispose() {}
}
