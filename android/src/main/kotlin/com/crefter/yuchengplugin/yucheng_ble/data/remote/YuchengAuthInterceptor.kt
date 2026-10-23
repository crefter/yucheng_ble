package com.crefter.yuchengplugin.yucheng_ble.data.remote

import android.util.Log
import com.crefter.yuchengplugin.yucheng_ble.data.local.YuchengTokenStorage
import com.crefter.yuchengplugin.yucheng_ble.data.local.strToken
import com.crefter.yuchengplugin.yucheng_ble.entity.YuchengFlavor
import okhttp3.Interceptor
import okhttp3.Response

class YuchengAuthInterceptor(
    private val tokenStorage: YuchengTokenStorage,
    private val flavor: YuchengFlavor,
) : Interceptor {
    companion object {
        private const val TAG = "YUCH_API Auth inter"
    }

    override fun intercept(chain: Interceptor.Chain): Response {
        val original = chain.request()


        val token = tokenStorage.getToken(flavor)?.access
        Log.d(TAG, "Intercepted request: ${original.url}")

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