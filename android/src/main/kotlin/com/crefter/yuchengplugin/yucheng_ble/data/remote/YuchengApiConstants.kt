package com.crefter.yuchengplugin.yucheng_ble.data.remote

object YuchengApiConstants {
    const val authDevBaseUrl: String = "https://auth.sleeptery.xdev.team"
    const val authPreProdBaseUrl: String = "https://auth.sleeptery.ru"
    const val sleepDevBaseUrl = "https://sleep.sleeptery.xdev.team"
    const val sleepPreProdBaseUrl = "https://sleep.sleeptery.ru"
    const val healthDevBaseUrl = "https://health.sleeptery.xdev.team"
    const val healthPreProdBaseUrl = "https://health.sleeptery.ru"

    const val sleep = "/sleep/ring/sleeptery/upload-v2"
    const val health = "/sleeptery-ring/upload-v2"
    const val refresh = "/auth/token/refresh"
}