package com.crefter.yuchengplugin.yucheng_ble

object YuchengBackgroundSleep {
    @Volatile
    var begin: ((baseUrl: String, address: String, bearer: String) -> ((String) -> Unit)?)? = null
}
