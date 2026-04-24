@file:OptIn(ExperimentalTime::class)

package com.crefter.yuchengplugin.yucheng_ble.data.remote

import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import com.crefter.yuchengplugin.yucheng_ble.YuchengHealthData
import com.crefter.yuchengplugin.yucheng_ble.YuchengHealthSportData
import com.crefter.yuchengplugin.yucheng_ble.YuchengSleepData
import com.crefter.yuchengplugin.yucheng_ble.YuchengSleepDataDetail
import com.crefter.yuchengplugin.yucheng_ble.YuchengSleepType
import com.crefter.yuchengplugin.yucheng_ble.YuchengSportData
import com.google.gson.GsonBuilder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.time.ExperimentalTime


private fun Long.toEpochMs(): Long {
    return when (this) {
        in 1_000_000_000_000L..9_999_999_999_999L -> this // ms
        in 1_000_000_000L..9_999_999_999L -> this * 1000 // sec
        else -> this // не трогаем, дальше отфильтруем
    }
}


val YuchengSleepType.json: String
    get() = name.lowercase()


val YuchengSleepDataDetail.startDate: LocalDateTime
    @RequiresApi(Build.VERSION_CODES.O)
    get() = Instant.ofEpochMilli(startTimeStamp.toEpochMs()).atZone(ZoneId.systemDefault())
        .toLocalDateTime()

val YuchengSleepDataDetail.endDate: LocalDateTime
    @RequiresApi(Build.VERSION_CODES.O)
    get() = Instant.ofEpochMilli(startTimeStamp.toEpochMs() + duration * 1000L)
        .atZone(ZoneId.systemDefault()).toLocalDateTime()

@RequiresApi(Build.VERSION_CODES.O)
fun YuchengSleepDataDetail.toJson() = mapOf(
    "start_date" to startDate.toString(),
    "end_date" to endDate.toString(),
    "duration_in_seconds" to duration,
    "type" to type.json
)

val YuchengSleepData.startDate: LocalDateTime
    @RequiresApi(Build.VERSION_CODES.O)
    get() = Instant.ofEpochMilli(startTimeStamp.toEpochMs()).atZone(ZoneId.systemDefault())
        .toLocalDateTime()

val YuchengSleepData.endDate: LocalDateTime
    @RequiresApi(Build.VERSION_CODES.O)
    get() = Instant.ofEpochMilli(endTimeStamp.toEpochMs()).atZone(ZoneId.systemDefault())
        .toLocalDateTime()


@RequiresApi(Build.VERSION_CODES.O)
fun YuchengSleepData.toJson() = mapOf(
    "start_date" to startDate.toString(),
    "end_date" to endDate.toString(),
    "deep_count" to deepCount,
    "light_count" to lightCount,
    "awake_count" to awakeCount,
    "deep_in_seconds" to deepInSeconds,
    "light_in_seconds" to lightInSeconds,
    "awake_in_seconds" to awakeInSeconds,
    "rem_in_seconds" to remInSeconds,
    "details" to details.map { it.toJson() }
)

val YuchengSportData.startDate: LocalDateTime
    @RequiresApi(Build.VERSION_CODES.O)
    get() = Instant.ofEpochMilli(startTimeStamp.toEpochMs()).atZone(ZoneId.systemDefault())
        .toLocalDateTime()

val YuchengSportData.endDate: LocalDateTime
    @RequiresApi(Build.VERSION_CODES.O)
    get() = Instant.ofEpochMilli(endTimeStamp.toEpochMs()).atZone(ZoneId.systemDefault())
        .toLocalDateTime()

@RequiresApi(Build.VERSION_CODES.O)
fun YuchengSportData.toJson() = mapOf(
    "start_date" to startDate.toString(),
    "end_date" to endDate.toString(),
    "distance" to distance,
    "calories" to calories,
    "steps" to steps
)

val YuchengHealthData.startDate: LocalDateTime
    @RequiresApi(Build.VERSION_CODES.O)
    get() = Instant.ofEpochMilli(startTimestamp.toEpochMs()).atZone(ZoneId.systemDefault())
        .toLocalDateTime()

@RequiresApi(Build.VERSION_CODES.O)
fun YuchengHealthData.toJson() = mapOf(
    "heart_value" to heartValue,
    "hrv_value" to hrvValue,
    "cvrr_value" to cvrrValue,
    "oxygen_value" to OOValue,
    "step_value" to stepValue,
    "dbp_value" to DBPValue,
    "temp_int_value" to tempIntValue,
    "temp_float_value" to tempFloatValue,
    "start_date" to startDate.toString(),
    "sbp_value" to SBPValue,
    "respiratory_rate_value" to respiratoryRateValue,
    "body_fat_int_value" to bodyFatIntValue,
    "body_fat_float_value" to bodyFatFloatValue,
    "blood_sugar_value" to bloodSugarValue
)

private fun Long.isValidEpochMs(): Boolean {
    val now = System.currentTimeMillis()

    return this < now + (7 * 24 * 60 * 60 * 1000)
}

class YuchengRepository(
    private val apiClient: OkHttpClient,
    private val apiConfig: YuchengApiConfig
) {
    companion object {
        private const val TAG = "YUCH_API Repo"
        private const val TAG_SLEEP = "$TAG sleep"
        private const val TAG_HEALTH = "$TAG health"
        private val gson = GsonBuilder().create()
    }


    @RequiresApi(Build.VERSION_CODES.O)
    suspend fun saveSleep(sleepData: List<YuchengSleepData>, deviceId: String) {
        withContext(Dispatchers.IO) {
            try {
                Log.i(TAG_SLEEP, "saveSleep")
                val offset = ZonedDateTime.now().offset.totalSeconds / 60

                val sleepDataJson = sleepData.map {
                    if (!it.startTimeStamp.isValidEpochMs()) {
                        Log.e(TAG_SLEEP, "NOT VALID SLEEP startTimestamp = ${it.startTimeStamp}")
                    }
                    if (!it.endTimeStamp.isValidEpochMs()) {
                        Log.e(TAG_SLEEP, "NOT VALID SLEEP endTimeStamp = ${it.endTimeStamp}")
                    }
                    return@map it.toJson()
                }
                val sleepJson = gson.toJson(sleepDataJson)
                Log.i(TAG_SLEEP, "Sleep json = $sleepJson")

                val json = "{" +
                        "\"device_id\": \"$deviceId\"," +
                        "\"utc_offset\": \"$offset\"," +
                        "\"source_platform\": \"SleepteryRing\"," +
                        "\"data\": {" +
                        "\"sleep_data\": $sleepJson" +
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
                Log.e(TAG_SLEEP, "Ошибка при отправке сна: $e")
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    suspend fun saveHealth(healthData: YuchengHealthSportData, deviceId: String) {
        withContext(Dispatchers.IO) {
            try {
                Log.i(TAG_HEALTH, "saveHealth")

                val offset = ZonedDateTime.now().offset.totalSeconds / 60
                val healthDataJson = healthData.healthData.map {
                    if (!it.startTimestamp.isValidEpochMs()) {
                        Log.e(TAG_HEALTH, "NOT VALID HEALTH startTimestamp = ${it.startTimestamp}")
                        return@map null
                    }
                    return@map it.toJson()
                }.filterNotNull()
                val healthJson = gson.toJson(healthDataJson)
                Log.e(TAG_HEALTH, "Health converted to json!")
                Log.i(TAG_HEALTH, "Health json = $healthJson")

                val sportDataJson = healthData.sportData.map {
                    if (!it.startTimeStamp.isValidEpochMs()) {
                        Log.e(TAG_HEALTH, "NOT VALID SPORT startTimestamp = ${it.startTimeStamp}")
                        return@map null
                    }
                    if (!it.endTimeStamp.isValidEpochMs()) {
                        Log.e(TAG_HEALTH, "NOT VALID SPORT endTimeStamp = ${it.endTimeStamp}")
                        return@map null
                    }
                    return@map it.toJson()
                }.filterNotNull()
                val sportJson = gson.toJson(sportDataJson)
                Log.e(TAG_HEALTH, "Sport converted to json!")
                Log.i(TAG_HEALTH, "Sport json = $sportJson")

                val json = "{" +
                        "\"device_id\": \"$deviceId\"," +
                        "\"utc_offset\": \"$offset\"," +
                        "\"source_platform\": \"SleepteryRing\"," +
                        "\"health_data\": $healthJson," +
                        "\"sport_data\": $sportJson" +
                        "}".trimIndent()

                val body = json.toRequestBody("application/json".toMediaType())
                val baseUrl = apiConfig.healthBaseUrl

                val url = "$baseUrl${YuchengApiConstants.health}"
                Log.e(TAG_HEALTH, "saveHealth: url = $url\njson = $json")

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