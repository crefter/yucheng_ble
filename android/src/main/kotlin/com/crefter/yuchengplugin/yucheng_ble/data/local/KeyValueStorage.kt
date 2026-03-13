package com.crefter.yuchengplugin.yucheng_ble.data.local

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.dayanruben.security.crypto.encryptedPreferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

interface KeyValueStorage<K, V> {
    suspend fun save(key: K, data: V)
    suspend fun read(key: K): V?
    suspend fun delete(key: K)
    fun values(key: K): Flow<V?>
}

val Context.yuchengBleStore: DataStore<Preferences> by preferencesDataStore(
    name = "yucheng_ble_storage"
)

val Context.yuchengEncryptedDataStore: DataStore<Preferences> by encryptedPreferencesDataStore(name = "yucheng_encrypted_data_store")

class DataStorage(val store: DataStore<Preferences>) : KeyValueStorage<String, String> {
    override suspend fun save(key: String, data: String) {
        store.edit { pref ->
            pref[stringPreferencesKey(key)] = data
        }
    }

    override suspend fun read(key: String): String? {
        return store.data.map { pref ->
            pref[stringPreferencesKey(key)]
        }.first()
    }

    override suspend fun delete(key: String) {
        store.edit { pref ->
            pref.remove(stringPreferencesKey(key))
        }
    }

    override fun values(key: String): Flow<String?> {
        return store.data.map {
            pref -> pref[stringPreferencesKey(key)]
        }
    }
}