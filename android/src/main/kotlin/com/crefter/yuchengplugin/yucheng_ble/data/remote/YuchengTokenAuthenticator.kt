package com.crefter.yuchengplugin.yucheng_ble.data.remote

import android.util.Log
import com.crefter.yuchengplugin.yucheng_ble.data.local.YuchengTokenStorage
import com.crefter.yuchengplugin.yucheng_ble.entity.YuchengFlavor
import kotlinx.coroutines.runBlocking
import okhttp3.Authenticator
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.Route
import org.json.JSONObject
import java.time.ZonedDateTime
import java.util.Calendar

data class YuchengTokens(
    val accessToken: String,
    val refreshToken: String
)

class YuchengTokenAuthenticator(private val tokenStorage: YuchengTokenStorage, private val apiConfig: YuchengApiConfig) : Authenticator {
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

            val currentToken = runBlocking { tokenStorage.getAccessToken() }
            if (currentToken == null) {
                return null
            }
            val requestToken = response.request.header("Authorization")
            Log.d(TAG, "currentToken = $currentToken, requestToken = $requestToken")

            // если токен уже обновился пока мы ждали lock
            if (requestToken != "Bearer $currentToken") {
                return response.request.newBuilder()
                    .header("Authorization", "Bearer $currentToken")
                    .build()
            }

            val refreshToken = runBlocking {  tokenStorage.getRefreshToken() }
            Log.d(TAG, "refresh token = $refreshToken")

            if (refreshToken == null) {
                Log.e(TAG, "refresh token null")
                return null
            }
            val newTokens = refreshTokens(refreshToken) ?: return null

            runBlocking {
                val expiresAt = Calendar.getInstance().timeInMillis
                tokenStorage.saveTokens(newTokens.accessToken, newTokens.refreshToken, expiresAt.toString())
            }

            return response.request.newBuilder()
                .header("Authorization", "Bearer ${newTokens.accessToken}")
                .build()
        }
    }

    fun refreshTokens(refreshToken: String?): YuchengTokens? {
        Log.e(TAG, "start refresh token")
        val client = OkHttpClient()

        val body = """
        {
          "refresh_token": "$refreshToken"
        }
    """.trimIndent()

        val requestBody = body.toRequestBody("application/json".toMediaType())
        val baseUrl = apiConfig.authBaseUrl
        val url = "$baseUrl${YuchengApiConstants.refresh}"
        Log.e(TAG, "refresh tokens: url = $url, body = ${requestBody}")

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
            Log.e(TAG, "refresh tokens: json = $json")

            return YuchengTokens(
                accessToken = json.getString("access_token"),
                refreshToken = json.getString("refresh_token")
            )
        }
    }
}