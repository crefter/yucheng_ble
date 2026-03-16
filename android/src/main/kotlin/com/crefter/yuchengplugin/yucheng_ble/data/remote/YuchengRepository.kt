package com.crefter.yuchengplugin.yucheng_ble.data.remote

import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import com.crefter.yuchengplugin.yucheng_ble.YuchengHealthSportData
import com.crefter.yuchengplugin.yucheng_ble.YuchengSleepData
import com.google.gson.Gson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.internal.platform.Platform
import java.time.ZonedDateTime

class YuchengRepository(private val apiClient: OkHttpClient, private val apiConfig: YuchengApiConfig) {
    companion object {
        private const val TAG = "YUCH_API Repo"
        private const val TAG_SLEEP = "$TAG sleep"
        private const val TAG_HEALTH = "$TAG health"
        private val gson = Gson()
    }


    @RequiresApi(Build.VERSION_CODES.O)
    suspend fun saveSleep(sleepData: List<YuchengSleepData>, deviceId: String) {
        withContext(Dispatchers.IO) {
            try {
                Log.i(TAG_SLEEP, "saveSleep")
                val offset = ZonedDateTime.now().offset.totalSeconds / 60

                val json = "{" +
                        "\"device_id\": \"$deviceId\"," +
                        "\"utc_offset\": \"$offset\"," +
                        "\"source_platform\": \"SleepteryRing\"," +
                        "\"data\": {" +
                        "\"sleep_data\": ${gson.toJson(sleepData)}" +
                        "}" +
                        "}".trimIndent()

                val body = json.toRequestBody("application/json".toMediaType())
                val baseUrl = apiConfig.sleepBaseUrl

                val url = "$baseUrl${YuchengApiConstants.sleep}"
                Log.i(TAG_SLEEP, "saveSleep: url = $url \n json = $json")

                val request = Request.Builder()
                    .header("Content-Type", "application/json")
                    .url(url)
                    .post(body)
                    .build()

                apiClient
                    .newCall(request).execute().use { response ->
                        if (!response.isSuccessful) {
                            Log.e(TAG_SLEEP, "Send failed ${response.code}")
                        } else {
                            Log.i(TAG_SLEEP, "Data sent successfully")
                        }
                    }
            } catch (e: Exception) {
                Log.e(TAG_SLEEP + " sleep", "Ошибка при отправке сна: $e")
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    suspend fun saveHealth(healthData: YuchengHealthSportData, deviceId: String) {
        withContext(Dispatchers.IO) {
            try {
                Log.i(TAG_HEALTH, "saveHealth")

                val offset = ZonedDateTime.now().offset.totalSeconds / 60

                val json = "{" +
                        "\"device_id\": \"$deviceId\"," +
                        "\"utc_offset\": \"$offset\"," +
                        "\"source_platform\": \"SleepteryRing\"," +
                        "\"health_data\": ${gson.toJson(healthData.healthData)}," +
                        "\"sport_data\": ${gson.toJson(healthData.sportData)}" +
                        "}".trimIndent()

                val body = json.toRequestBody("application/json".toMediaType())
                val baseUrl = apiConfig.healthBaseUrl

                val url = "$baseUrl${YuchengApiConstants.health}"
                Log.i(TAG_HEALTH, "saveHealth: url = $url \n json = $json")

                val request = Request.Builder()
                    .header("Content-Type", "application/json")
                    .url(url)
                    .post(body)
                    .build()

                apiClient
                    .newCall(request).execute().use { response ->
                        if (!response.isSuccessful) {
                            Log.e(TAG_HEALTH, "Send failed ${response.code}")
                        } else {
                            Log.i(TAG_HEALTH, "Data sent successfully")
                        }
                    }


            } catch (e: Exception) {
                Log.e(TAG_HEALTH, "Ошибка при отправке здоровья: $e")
            }
        }
    }
}