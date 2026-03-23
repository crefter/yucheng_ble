package com.crefter.yuchengplugin.yucheng_ble.entity

enum class YuchengFlavor {
    dev,
    prod;

    companion object {
        fun fromString(value: String?): YuchengFlavor {
            if (value == "preProd" || value == "prod") return prod
            return dev
        }
    }
}