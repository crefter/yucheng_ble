package com.crefter.yuchengplugin.yucheng_ble.data.remote

import android.util.Base64
import org.json.JSONObject

internal fun sameHistoryAccount(first: String, second: String): Boolean {
    if (first == second) return true
    fun subject(token: String): String? = try {
        val parts = token.split('.')
        val json = JSONObject(String(Base64.decode(parts[1], Base64.URL_SAFE)))
        listOf("uuid", "sub", "user_id", "userId").firstNotNullOfOrNull { key ->
            (json.opt(key) as? String)?.takeIf { it.isNotEmpty() }
        }
    } catch (_: Exception) { null }
    val owner = subject(first)
    return owner != null && owner == subject(second)
}
