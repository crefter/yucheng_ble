package com.crefter.yuchengplugin.yucheng_ble.data.local

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
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

private fun initEncryptDataStore(context: Context): SharedPreferences {
    val masterKey = MasterKey.Builder(context)
        .setKeyGenParameterSpec(
            KeyGenParameterSpec.Builder(
                MasterKey.DEFAULT_MASTER_KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setKeySize(256).build()
        )
        .build()

    val sharedPreferences = EncryptedSharedPreferences.create(
        context,
        "FlutterSecureStorage",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )
    return sharedPreferences
}

fun yuchengEncryptedDataStore(context: Context): SharedPreferences {
    val TAG = "YUCH_API EncryptedDataStore"
    try {
        return initEncryptDataStore(context)
    } catch (e: Exception) {
        Log.e(TAG, "$e")
        try {
            // Delete all encrypted data
            val dataPrefs = context.getSharedPreferences(
                "FlutterSecureStorage",
                Context.MODE_PRIVATE
            )
            dataPrefs.edit().clear().apply()
            Log.d(TAG, "Deleted all encrypted data")

            // Delete stored wrapped keys
            val keyPrefs = context.getSharedPreferences(
                "FlutterSecureKeyStorage",
                Context.MODE_PRIVATE
            )
            keyPrefs.edit().clear().apply()

            Log.d(TAG, "Deleted wrapped keys from SharedPreferences")
            return initEncryptDataStore(context)
        } catch (cleanupError: java.lang.Exception) {
            Log.e(TAG, "Failed to clean up after key mismatch", cleanupError)
            return initEncryptDataStore(context)
        }
    }
}

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