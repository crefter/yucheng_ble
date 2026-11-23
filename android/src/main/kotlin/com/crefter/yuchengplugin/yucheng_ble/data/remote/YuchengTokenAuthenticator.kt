@file:OptIn(ExperimentalTime::class)

package com.crefter.yuchengplugin.yucheng_ble.data.remote

import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import com.crefter.yuchengplugin.yucheng_ble.YuchengCore
import com.crefter.yuchengplugin.yucheng_ble.data.local.YuchengTokenStorage
import com.crefter.yuchengplugin.yucheng_ble.entity.YuchengAuthToken
import com.crefter.yuchengplugin.yucheng_ble.entity.YuchengFlavor
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import okhttp3.Authenticator
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.Route
import org.json.JSONObject
import kotlin.time.Clock
import kotlin.time.ExperimentalTime


class YuchengTokenAuthenticator(
    private val tokenStorage: YuchengTokenStorage,
    private val apiConfig: YuchengApiConfig,
    private val flavor: YuchengFlavor
) : Authenticator {
    companion object {
        private const val TAG = "YUCH_API Token auth"
    }

    private val lock = Any()

    private fun responseCount(response: Response): Int {
        var result = 1
        var prior = response.priorResponse
        while (prior != null) {
            result++
            prior = prior.priorResponse
        }
        return result
    }

    @RequiresApi(Build.VERSION_CODES.O)
    override fun authenticate(route: Route?, response: Response): Request? {
        if (responseCount(response) >= 2) {
            return null
        }
        synchronized(lock) {

            val credentials = tokenStorage.getToken(flavor) ?: return null
            val currentToken = credentials.access
            val requestToken = response.request.header("Authorization")


            // если токен уже обновился пока мы ждали lock
            if (requestToken != "Bearer $currentToken") {
                val requested = requestToken?.removePrefix("Bearer ") ?: return null
                if (!sameHistoryAccount(requested, currentToken)) return null
                return response.request.newBuilder()
                    .header("Authorization", "Bearer $currentToken")
                    .build()
            }

            val refreshToken = credentials.refresh
            Log.i(TAG, "start refreshing!")
            YuchengCore.isTokenRefreshing.value = true
            val newToken = try {
                val refreshed = refreshTokens(refreshToken) ?: return null
                if (!tokenStorage.saveRefreshedToken(refreshed, flavor, refreshToken)) return null
                refreshed
            } finally {
                YuchengCore.isTokenRefreshing.value = false
            }

            return response.request.newBuilder()
                .header("Authorization", "Bearer ${newToken.accessToken}")
                .build()
        }
    }

    fun refreshTokens(refreshToken: String?): YuchengAuthToken? {
        Log.e(TAG, "start refresh token")
        val client = ApiClient.getDefaultClient()

        val body = """
        {
          "refresh_token": "$refreshToken"
        }
    """.trimIndent()

        val requestBody = body.toRequestBody("application/json".toMediaType())
        val baseUrl = apiConfig.authBaseUrl
        val url = "$baseUrl${YuchengApiConstants.refresh}"

        val request = Request.Builder()
            .url(url)
            .post(requestBody)
            .build()
        client.newCall(request).execute().use { response ->

            if (!response.isSuccessful) {
                Log.e(TAG, "refresh tokens: response not successful = $response")
                return null
            }

            val body = response.body.string()
            val json = JSONObject(body)

            return YuchengAuthToken(
                accessToken = json.getString("access_token"),
                refreshToken = json.getString("refresh_token"),
                issuedAt = Clock.System.now()
            )
        }
    }
}