package com.crefter.yuchengplugin.yucheng_ble.data.local

class YuchengTokenStorage(private val storage: KeyValueStorage<String, String>) {

    suspend fun getAccessToken(): String? {
        return storage.read(accessKey)
    }

    suspend fun getRefreshToken(): String? {
        return storage.read(refreshKey)
    }

    suspend fun saveTokens(access: String, refresh: String) {
        storage.save(accessKey, access)
        storage.save(refreshKey, refresh)
    }

    suspend fun clear() {
        storage.delete(accessKey)
        storage.delete(refreshKey)
    }

    companion object {
        val accessKey = "access_token"
        val refreshKey = "refresh_token"
    }
}