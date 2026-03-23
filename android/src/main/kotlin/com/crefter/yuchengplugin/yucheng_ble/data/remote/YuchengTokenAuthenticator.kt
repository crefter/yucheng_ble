@file:OptIn(ExperimentalTime::class)

package com.crefter.yuchengplugin.yucheng_ble.data.remote

import android.util.Log
import com.crefter.yuchengplugin.yucheng_ble.data.local.YuchengTokenStorage
import com.crefter.yuchengplugin.yucheng_ble.data.local.strToken
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

    override fun authenticate(route: Route?, response: Response): Request? {
        if (responseCount(response) >= 2) {
            return null
        }
        synchronized(lock) {

            val currentToken = tokenStorage.getToken(flavor)?.access
            if (currentToken == null) {
                Log.e(
                    TAG,
                    "access token null"
                )
                return null
            }
            val requestToken = response.request.header("Authorization")
            Log.d(
                TAG,
                "currentToken = ${currentToken.strToken()}, requestToken = $requestToken"
            )

            // если токен уже обновился пока мы ждали lock
            if (requestToken != "Bearer $currentToken") {
                return response.request.newBuilder()
                    .header("Authorization", "Bearer $currentToken")
                    .build()
            }

            val refreshToken = tokenStorage.getToken(flavor)?.refresh
            Log.d(
                TAG,
                "refresh token = ${refreshToken.strToken()}"
            )

            if (refreshToken == null) {
                Log.e(
                    TAG,
                    "refresh token null"
                )
                return null
            }
            val newToken = refreshTokens(refreshToken) ?: return null

            CoroutineScope(Dispatchers.Main).launch {
                tokenStorage.saveTokens(newToken, flavor)
            }

            return response.request.newBuilder()
                .header("Authorization", "Bearer ${newToken.accessToken}")
                .build()
        }
    }

    fun refreshTokens(refreshToken: String?): YuchengAuthToken? {
        Log.e(
            TAG,
            "start refresh token"
        )
        val client = ApiClient.getDefaultClient()

        val body = """
        {
          "refresh_token": "$refreshToken"
        }
    """.trimIndent()

        val requestBody = body.toRequestBody("application/json".toMediaType())
        val baseUrl = apiConfig.authBaseUrl
        val url = "$baseUrl${YuchengApiConstants.refresh}"
        Log.e(
            TAG,
            "refresh tokens: url = $url, refreshToken = ${refreshToken.strToken()}"
        )

        val request = Request.Builder()
            .url(url)
            .post(requestBody)
            .build()

        client.newCall(request).execute().use { response ->

            if (!response.isSuccessful) {
                Log.e(
                    TAG,
                    "refresh tokens: response not successful = $response"
                )
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