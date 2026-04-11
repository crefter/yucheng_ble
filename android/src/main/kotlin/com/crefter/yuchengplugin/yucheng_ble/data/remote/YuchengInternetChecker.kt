package com.crefter.yuchengplugin.yucheng_ble.data.remote

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request

object YuchengInternetChecker {
    // Специальный endpoint + .ru fallback
    private const val GOOGLE_CHECK_URL = "https://clients3.google.com/generate_204"
    private const val RU_CHECK_URL = "https://ya.ru"

    suspend fun hasInternet(client: OkHttpClient): Boolean = withContext(Dispatchers.IO) {
        coroutineScope {
            val google = async { checkUrl(GOOGLE_CHECK_URL, client) }
            val ru = async { checkUrl(RU_CHECK_URL, client) }

            google.await() || ru.await()
        }
    }

    private fun checkUrl(url: String, client: OkHttpClient): Boolean {
        return try {
            val request = Request.Builder()
                .url(url)
                .head()
                .build()

            client.newCall(request).execute().use { response ->
                response.isSuccessful
            }
        } catch (e: Exception) {
            false
        }
    }
}