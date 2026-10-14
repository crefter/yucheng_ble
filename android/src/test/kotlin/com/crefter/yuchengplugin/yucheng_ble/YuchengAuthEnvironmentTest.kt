@file:OptIn(kotlin.time.ExperimentalTime::class)

package com.crefter.yuchengplugin.yucheng_ble

import android.content.SharedPreferences
import com.crefter.yuchengplugin.yucheng_ble.data.local.YuchengTokenStorage
import com.crefter.yuchengplugin.yucheng_ble.data.remote.ApiClient
import com.crefter.yuchengplugin.yucheng_ble.data.remote.YuchengApiConfig
import com.crefter.yuchengplugin.yucheng_ble.entity.YuchengFlavor
import com.crefter.yuchengplugin.yucheng_ble.entity.YuchengAuthToken
import kotlin.test.Test
import kotlin.test.assertNotSame
import kotlin.test.assertSame
import kotlin.test.assertNull
import kotlin.test.assertFalse
import org.mockito.ArgumentMatchers.anyString
import org.mockito.Mockito.*
import kotlin.time.Instant

class YuchengAuthEnvironmentTest {
    private fun storage(): YuchengTokenStorage {
        val values = mutableMapOf<String, String>()
        val prefs = mock(SharedPreferences::class.java)
        val editor = mock(SharedPreferences.Editor::class.java)
        `when`(prefs.getString(anyString(), isNull())).thenAnswer { values[it.getArgument(0)] }
        `when`(prefs.edit()).thenReturn(editor)
        `when`(editor.putString(anyString(), anyString())).thenAnswer {
            values[it.getArgument(0)] = it.getArgument(1)
            editor
        }
        `when`(editor.remove(anyString())).thenAnswer {
            values.remove(it.getArgument<String>(0))
            editor
        }
        return YuchengTokenStorage(prefs)
    }

    @Test
    fun clientChangesWithEnvironment() {
        ApiClient.reset()
        val storage = storage()
        val dev = YuchengApiConfig("https://sleep.dev.test", "https://health.dev.test", "https://auth.dev.test")
        val prod = YuchengApiConfig("https://sleep.prod.test", "https://health.prod.test", "https://auth.prod.test")
        val first = ApiClient.getClient(storage, dev, YuchengFlavor.dev)
        assertSame(first, ApiClient.getClient(storage, dev, YuchengFlavor.dev))
        assertNotSame(first, ApiClient.getClient(storage, prod, YuchengFlavor.prod))
        ApiClient.reset()
    }

    @Test
    fun lateRefreshCannotRestoreLoggedOutToken() {
        val storage = storage()
        val old = YuchengAuthToken(accessToken = "access", refreshToken = "refresh", issuedAt = Instant.fromEpochMilliseconds(1000))
        storage.saveTokens(old, YuchengFlavor.prod)
        storage.clear(YuchengFlavor.prod)
        val refreshed = YuchengAuthToken(accessToken = "next-access", refreshToken = "next-refresh", issuedAt = Instant.fromEpochMilliseconds(2000))
        assertFalse(storage.saveRefreshedToken(refreshed, YuchengFlavor.prod, "refresh"))
        assertNull(storage.getToken(YuchengFlavor.prod))
    }

    @Test
    fun emptyEnvironmentDoesNotReturnAnotherEnvironmentsToken() {
        val storage = storage()
        storage.saveTokens(YuchengAuthToken(accessToken = "access", refreshToken = "refresh", issuedAt = Instant.fromEpochMilliseconds(1000)), YuchengFlavor.prod)
        assertNull(storage.getToken(YuchengFlavor.dev))
    }
}
