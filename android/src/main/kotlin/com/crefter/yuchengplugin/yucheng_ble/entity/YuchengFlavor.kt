package com.crefter.yuchengplugin.yucheng_ble.entity

enum class YuchengFlavor {
    dev,
    preProd;

    companion object {
        fun fromString(value: String?): YuchengFlavor {
            if (value == "preProd") return preProd
            return dev
        }
    }
}