package com.crefter.yuchengplugin.yucheng_ble.data.local

import android.util.Log
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map


class YuchengBleStorage(private val storage: KeyValueStorage<String, String>) {
    companion object {
        private const val YUCH_API = "YUCH_API STORAGE"
        private const val DELAY_KEY = "yucheng_delay_key"
        private const val SERVICE_ON = "yucheng_service_on"
        private const val FLAVOR = "yucheng_flavor_name"
    }

    suspend fun saveDelay(delay: Int) {
        Log.d(YUCH_API, "Save delay: $delay")
        storage.save(DELAY_KEY, delay.toString())
    }

    suspend fun readDelay(): Int? {
        val delay = storage.read(DELAY_KEY)
        Log.d(YUCH_API, "Read delay: $delay")
        return delay?.toInt()
    }

    suspend fun readServiceOn(): Boolean {
        val on = storage.read(SERVICE_ON)?.toBoolean()
        Log.d(YUCH_API, "Read service on: $on")
        return on ?: false
    }

    suspend fun saveServiceOn(on: Boolean) {
        Log.d(YUCH_API, "Save service on: $on")
        storage.save(SERVICE_ON, on.toString())
    }

    fun onServiceOn(): Flow<Boolean?> {
        return storage.values(SERVICE_ON).map { value -> value?.toBoolean() }
    }

    suspend fun readFlavor(): String? {
        val flavor = storage.read(FLAVOR)
        Log.d(YUCH_API, "Read flavor on: $flavor")
        return flavor
    }

    suspend fun saveFlavor(flavor: String) {
        Log.d(YUCH_API, "Save flavor: $flavor")
        storage.save(FLAVOR, flavor)
    }
}