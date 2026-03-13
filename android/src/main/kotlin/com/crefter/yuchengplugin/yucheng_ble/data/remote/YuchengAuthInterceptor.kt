package com.crefter.yuchengplugin.yucheng_ble.data.remote

import com.crefter.yuchengplugin.yucheng_ble.data.local.YuchengTokenStorage
import kotlinx.coroutines.runBlocking
import okhttp3.Interceptor
import okhttp3.Response

class YuchengAuthInterceptor(private val tokenStorage: YuchengTokenStorage) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {

        val original = chain.request()

        val token = runBlocking { tokenStorage.getAccessToken() }

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