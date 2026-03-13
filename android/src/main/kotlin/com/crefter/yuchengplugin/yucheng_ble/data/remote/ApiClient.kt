package com.crefter.yuchengplugin.yucheng_ble.data.remote

import okhttp3.OkHttpClient
import kotlin.time.Duration.Companion.seconds

class ApiClient(private val authInterceptor: YuchengAuthInterceptor, private val tokenAuthenticator: YuchengTokenAuthenticator) {

    private var client: OkHttpClient? = null
    private val lock = Any()

    fun getClient(): OkHttpClient {
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
                .addInterceptor(authInterceptor)
                .authenticator(tokenAuthenticator)
                .build()
            return client!!
        }
    }
}
