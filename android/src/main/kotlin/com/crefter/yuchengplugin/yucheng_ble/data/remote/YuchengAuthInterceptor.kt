package com.crefter.yuchengplugin.yucheng_ble.data.remote

import android.util.Log
import com.crefter.yuchengplugin.yucheng_ble.data.local.YuchengTokenStorage
import kotlinx.coroutines.runBlocking
import okhttp3.Interceptor
import okhttp3.Response

class YuchengAuthInterceptor(private val tokenStorage: YuchengTokenStorage) : Interceptor {
    companion object {
        private const val TAG = "YUCH_API Auth inter"
    }

    override fun intercept(chain: Interceptor.Chain): Response {
        val original = chain.request()
        Log.d(TAG, "original request = $original")

        val token = runBlocking { tokenStorage.getAccessToken() }
        Log.d(TAG, "access token = $token")

        val request = if (token != null) {
            original.newBuilder()
                .addHeader("Authorization", "Bearer $token")
                .build()
        } else {
            original
        }

        return chain.proceed(request)
    }
}