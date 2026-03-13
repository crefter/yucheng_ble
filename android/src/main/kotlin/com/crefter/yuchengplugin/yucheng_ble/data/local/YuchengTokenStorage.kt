package com.crefter.yuchengplugin.yucheng_ble.data.local

import android.util.Log

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

    suspend fun saveTokens(access: String, refresh: String) {
        storage.save(accessKey, access)
        storage.save(refreshKey, refresh)
        Log.d(TAG, "saveTokens: access = $access, refresh = $refresh")
    }

    suspend fun clear() {
        storage.delete(accessKey)
        storage.delete(refreshKey)
    }

    companion object {
        private val accessKey = "access_token"
        private val refreshKey = "refresh_token"
        private const val TAG = "YUCH_API Token storage"
    }
}