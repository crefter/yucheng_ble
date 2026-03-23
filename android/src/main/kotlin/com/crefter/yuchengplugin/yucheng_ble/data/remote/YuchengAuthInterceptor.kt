package com.crefter.yuchengplugin.yucheng_ble.data.remote

import android.util.Log
import com.crefter.yuchengplugin.yucheng_ble.data.local.YuchengTokenStorage
import com.crefter.yuchengplugin.yucheng_ble.data.local.strToken
import okhttp3.Interceptor
import okhttp3.Response

class YuchengAuthInterceptor(private val tokenStorage: YuchengTokenStorage) : Interceptor {
    companion object {
        private const val TAG = "YUCH_API Auth inter"
    }

    override fun intercept(chain: Interceptor.Chain): Response {
        val original = chain.request()
        Log.d(TAG, "original request = $original")

        val token = tokenStorage.getToken()?.access
        Log.d(TAG, "Intercepted request: ${original.url}, token=${token.strToken()}")

        val request = if (token != null) {
            original.newBuilder()
                .header("Authorization", "Bearer $token")
                .build()
        } else {
            original
        }

        return chain.proceed(request)
    }
}