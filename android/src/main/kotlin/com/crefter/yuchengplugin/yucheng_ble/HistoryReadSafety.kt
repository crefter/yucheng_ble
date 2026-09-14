package com.crefter.yuchengplugin.yucheng_ble

/** No read/ack token exists in the delete API. An incomplete read permanently
 * blocks automatic clear in this process, including after a later full read.
 * Explicit deleteAllData/factory reset retain their separate behavior. */
internal class HistoryReadSafety {
    private var active = 0
    private var blocked = false
    private var deleting = false

    @Synchronized fun begin(): Boolean {
        if (deleting) { blocked = true; return false }
        active++
        return true
    }
    @Synchronized fun finish(complete: Boolean) {
        active--
        if (!complete) blocked = true
    }
    @Synchronized fun beginDelete(): Boolean {
        if (active != 0 || blocked || deleting) return false
        deleting = true
        return true
    }
    @Synchronized fun finishDelete() { deleting = false }

    companion object {
        val sleep = HistoryReadSafety()
        val health = HistoryReadSafety()
    }
}
