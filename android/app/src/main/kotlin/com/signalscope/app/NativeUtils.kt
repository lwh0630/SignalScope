package com.signalscope.app

/** `CellInfo.UNAVAILABLE` (Integer.MAX_VALUE) means "the modem did not report this value". */
internal fun Int.validOrNull(): Int? = if (this == Int.MAX_VALUE) null else this

/** `CellInfo.UNAVAILABLE_LONG` (Long.MAX_VALUE) means "not reported". */
internal fun Long.validOrNull(): Long? = if (this == Long.MAX_VALUE) null else this

internal fun String?.nullIfBlank(): String? = if (this.isNullOrBlank()) null else this

/** Runs [block] and returns null if the platform throws (missing permission, unsupported, ...). */
internal inline fun <T> safe(block: () -> T?): T? = try {
    block()
} catch (_: SecurityException) {
    null
} catch (_: RuntimeException) {
    null
}
