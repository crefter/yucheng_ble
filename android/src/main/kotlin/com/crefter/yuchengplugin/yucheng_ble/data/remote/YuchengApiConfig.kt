package com.crefter.yuchengplugin.yucheng_ble.data.remote

import com.crefter.yuchengplugin.yucheng_ble.entity.YuchengFlavor


data class YuchengApiConfig(
    val sleepBaseUrl: String,
    val healthBaseUrl: String,
    val authBaseUrl: String,
) {
    companion object {
        fun fromFlavor(flavor: YuchengFlavor) : YuchengApiConfig {
            return when (flavor) {
                YuchengFlavor.dev -> devApiConfig
                YuchengFlavor.preProd -> preProdApiConfig
            }
        }
    }
}

val devApiConfig = YuchengApiConfig(
    sleepBaseUrl = YuchengApiConstants.sleepDevBaseUrl,
    healthBaseUrl = YuchengApiConstants.healthDevBaseUrl,
    authBaseUrl = YuchengApiConstants.authDevBaseUrl,
)

val preProdApiConfig = YuchengApiConfig(
    sleepBaseUrl = YuchengApiConstants.sleepPreProdBaseUrl,
    healthBaseUrl = YuchengApiConstants.healthPreProdBaseUrl,
    authBaseUrl = YuchengApiConstants.authPreProdBaseUrl,
)