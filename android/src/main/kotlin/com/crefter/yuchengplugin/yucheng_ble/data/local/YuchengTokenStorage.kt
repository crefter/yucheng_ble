package com.crefter.yuchengplugin.yucheng_ble.data.local

import android.icu.util.Calendar
import android.util.Log
import com.crefter.yuchengplugin.yucheng_ble.YuchengToken

class YuchengTokenStorage(private val storage: KeyValueStorage<String, String>) {
    suspend fun getAccessToken(): String? {
        val access = storage.read(accessKey)
        Log.d(TAG, "getAccessToken = $access")
        return access
    }

    suspend fun getRefreshToken(): String? {
        val refresh = storage.read(refreshKey)
        Log.d(TAG, "getRefreshToken = $refresh")
        return refresh
    }

    suspend fun getExpiresAt(): Long? {
        val expiresAtStr = storage.read(expiresAtKey)
        Log.d(TAG, "getExpiresAt = $expiresAtStr")
        return expiresAtStr?.toLong()
    }

    suspend fun getToken(): YuchengToken? {
        val access = getAccessToken()
        val refresh = getRefreshToken()
        val timestamp = getExpiresAt() ?: Calendar.getInstance().timeInMillis
        if (access == null || refresh == null) return null
        val token = YuchengToken(access, refresh, timestamp)
        return token
    }
    suspend fun saveTokens(access: String, refresh: String, expiresAt: String) {
        storage.save(accessKey, access)
        storage.save(refreshKey, refresh)
        storage.save(expiresAtKey, expiresAt)
        Log.d(TAG, "saveTokens: access = $access, refresh = $refresh, expiresAt = $expiresAt")
    }

    suspend fun clear() {
        storage.delete(accessKey)
        storage.delete(refreshKey)
    }

    companion object {
        private val accessKey = "access_token"
        private val refreshKey = "refresh_token"
        private val expiresAtKey = "expires_at_key"
        private const val TAG = "YUCH_API Token storage"
    }
}