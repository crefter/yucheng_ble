@file:OptIn(ExperimentalTime::class)

package com.crefter.yuchengplugin.yucheng_ble.data.local

import android.content.SharedPreferences
import android.icu.util.Calendar
import android.util.Log
import androidx.core.content.edit
import com.crefter.yuchengplugin.yucheng_ble.YuchengToken
import com.crefter.yuchengplugin.yucheng_ble.entity.YuchengAuthToken
import com.crefter.yuchengplugin.yucheng_ble.entity.YuchengFlavor
import kotlinx.serialization.json.Json
import kotlin.time.ExperimentalTime
import kotlin.time.Instant


class YuchengTokenStorage(private val storage: SharedPreferences) {
    private var savedToken: YuchengToken? = null
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
    }

    fun getToken(): YuchengToken? {
        return savedToken
    }

    fun getToken(flavor: YuchengFlavor): YuchengToken? {
        Log.d(TAG, "getToken: flavor = $flavor")
        try {
            val authTokenStr = storage.getString(key(flavor), null)
            val qcAuthToken =
                if (authTokenStr == null) null else json.decodeFromString<YuchengAuthToken>(
                    authTokenStr
                )
            val access = qcAuthToken?.accessToken
            val refresh = qcAuthToken?.refreshToken
            val timestamp =
                qcAuthToken?.issuedAt?.toEpochMilliseconds() ?: Calendar.getInstance().timeInMillis
            Log.d(
                TAG,
                "getToken: timestamp = ${Instant.fromEpochMilliseconds(timestamp)}," +
                        " access = ${access.strToken()}, refresh = ${refresh.strToken()}"
            )
            if (access == null || refresh == null) return null
            val token = YuchengToken(access, refresh, timestamp)
            savedToken = token
            return token
        } catch (e: Exception) {
            Log.e(TAG, "$e")
            return null
        }
    }

    fun saveTokens(token: YuchengAuthToken, flavor: YuchengFlavor) {
        Log.d(TAG, "saveTokens: flavor = $flavor")
        try {
            val json = json.encodeToString(token)
            storage.edit {
                putString(key(flavor), json)
                apply()
            }
            savedToken = YuchengToken(
                token.accessToken,
                token.refreshToken ?: "",
                token.issuedAt?.toEpochMilliseconds() ?: 0
            )
        } catch (e: Exception) {
            Log.e(TAG, "$e")
        }
        Log.d(
            TAG,
            "saveTokens! issuedAt = ${token.issuedAt} access = ${token.accessToken.strToken()}, refresh = ${token.refreshToken.strToken()}"
        )
    }

    fun clear(flavor: YuchengFlavor) {
        try {
            storage.edit {
                remove(key(flavor))
                apply()
            }
        } catch (e: Exception) {
            Log.e(TAG, "$e")
        }
    }

    private fun key(flavor: YuchengFlavor): String {
        return DEFAULT_KEY_PREFIX + "_" + flavor.name + "_" + TOKEN_KEY
    }

    companion object {
        private const val TOKEN_KEY = "auth_token"
        private const val TAG = "YUCH_API Token storage"
        const val DEFAULT_KEY_PREFIX: String =
            "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg"
    }
}

fun String?.strToken(): String {
    if (this.isNullOrEmpty()) return ""
    return if (this.length > 10) {
        this.substring(this.length - 10)
    } else {
        ""
    }
}