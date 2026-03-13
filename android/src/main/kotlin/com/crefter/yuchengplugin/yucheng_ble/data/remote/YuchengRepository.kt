package com.crefter.yuchengplugin.yucheng_ble.data.remote

import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import com.crefter.yuchengplugin.yucheng_ble.YuchengHealthSportData
import com.crefter.yuchengplugin.yucheng_ble.YuchengSleepData
import com.google.gson.Gson
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.time.ZonedDateTime

class YuchengRepository(private val apiClient: OkHttpClient, private val apiConfig: YuchengApiConfig) {
    @RequiresApi(Build.VERSION_CODES.O)
    fun saveSleep(sleepData: List<YuchengSleepData>, deviceId: String) {
        val gson = Gson()

        val offset = ZonedDateTime.now().offset.totalSeconds / 60

        val json = "{" +
                "\"device_id\": \"$deviceId\"," +
                "\"utc_offset\": $offset," +
                "\"source_platform\": \"SleepteryRing\"," +
                "\"data\": {" +
                "\"sleep_data\": ${gson.toJson(sleepData)}" +
                "}" +
                "}".trimIndent()

        val body = json.toRequestBody("application/json".toMediaType())
        val baseUrl = apiConfig.sleepBaseUrl

        val url = "$baseUrl${YuchengApiConstants.sleep}"

        val request = Request.Builder()
            .url(url)
            .post(body)
            .build()

        val response = apiClient
            .newCall(request).execute()

        if (!response.isSuccessful) {
            Log.e("API", "Send failed ${response.code}")
        } else {
            Log.i("API", "Data sent successfully")
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    fun saveHealth(healthData: YuchengHealthSportData, deviceId: String) {
        val gson = Gson()

        val offset = ZonedDateTime.now().offset.totalSeconds / 60

        val json = "{" +
                "\"device_id\": \"$deviceId\"," +
                "\"utc_offset\": $offset," +
                "\"source_platform\": \"SleepteryRing\"," +
                "\"health_data\": ${gson.toJson(healthData.healthData)}," +
                "\"sport_data\": ${gson.toJson(healthData.sportData)}" +
                "}".trimIndent()

        val body = json.toRequestBody("application/json".toMediaType())
        val baseUrl = apiConfig.healthBaseUrl

        val url = "$baseUrl${YuchengApiConstants.health}"

        val request = Request.Builder()
            .url(url)
            .post(body)
            .build()

        val response = apiClient
            .newCall(request).execute()

        if (!response.isSuccessful) {
            Log.e("API", "Send failed ${response.code}")
        } else {
            Log.i("API", "Data sent successfully")
        }
    }
}