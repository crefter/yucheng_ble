package com.crefter.yuchengplugin.yucheng_ble.data.remote

import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import com.crefter.yuchengplugin.yucheng_ble.data.local.YuchengTokenStorage
import com.crefter.yuchengplugin.yucheng_ble.entity.YuchengFlavor
import okhttp3.ConnectionPool
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit
import kotlin.time.Duration.Companion.seconds

object ApiClient {
    private const val TAG = "YUCH_API api client"

    private var client: OkHttpClient? = null
    private val lock = Any()

    @RequiresApi(Build.VERSION_CODES.GINGERBREAD)
    fun getClient(tokenStorage: YuchengTokenStorage,
                  apiConfig: YuchengApiConfig, flavor: YuchengFlavor): OkHttpClient {
        if (client != null) {
            return client!!
        }
        synchronized(lock) {
            if (client != null) {
                return client!!
            }
            client = OkHttpClient.Builder()
                .connectTimeout(15.seconds)
                .writeTimeout(45.seconds)
                .readTimeout(45.seconds)
                .retryOnConnectionFailure(true)
                .addNetworkInterceptor { chain ->
                    val request = chain.request()
                    Log.d(TAG, "REQUEST: ${request.url}")
                    val response = chain.proceed(request)
                    Log.d(TAG, "RESPONSE: ${response.code}")
                    response
                }
                .connectionPool(ConnectionPool(5, 5, TimeUnit.MINUTES))
                .addInterceptor(YuchengAuthInterceptor(tokenStorage = tokenStorage))
                .authenticator(YuchengTokenAuthenticator(tokenStorage, apiConfig, flavor))
                .build()
            return client!!
        }
    }

    fun getDefaultClient() : OkHttpClient {
        return OkHttpClient()
    }

    fun getClientForCheckInternet() : OkHttpClient {
        return OkHttpClient.Builder()
            .connectTimeout(3, TimeUnit.SECONDS)
            .readTimeout(3, TimeUnit.SECONDS)
            .callTimeout(3, TimeUnit.SECONDS)
            .build()
    }
}
