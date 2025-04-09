package com.crefter.yuchengplugin.yucheng_ble

import YuchengSleepDataDetail
import YuchengSleepDataEvent
import com.google.gson.Gson
import com.google.gson.annotations.SerializedName

private class SleepDataBean(
    val deepSleepCount: Int,// deepSleepCount
    val lightSleepCount: Int, // lightSleepCount
    val startTime: Long,// startSleepTime
    val endTime: Long?, // endSleepTime
    val deepSleepTotal: Int, // deepSleepTotal
    val lightSleepTotal: Int, // lightSleepTotal
    @SerializedName(
        value =
            "rapidEyeMovementTotal", alternate = ["remTimes"]
    )
    var rapidEyeMovementTotal: Int, // eyeMovementTotal
    val wakeCount: Int,// number of times awake
    val wakeDuration: Int,// length of time awake
    val sleepData: List<SleepData> = ArrayList(), // sleep data
)

private class SleepData(
    @SerializedName(
        value =
            "sleepStartTime", alternate = ["stime"]
    )
    val sleepStartTime: Long, // start time

    @SerializedName(
        value =
            "sleepLen", alternate = ["sleepLong"]
    )
    val sleepLen: Int, // sleep length
    var sleepType: Int, // deepSleepLightSleep flag, flag type is SleepType below)
)

class YuchengSleepDataConverter(private val gson: Gson) {
    fun convert(sleepDataBean: Any?): YuchengSleepDataEvent {
        val converted = gson.fromJson(sleepDataBean.toString(), SleepDataBean::class.java)
        val deepSleepCount = converted.deepSleepCount.toLong()
        val isOldFormat = deepSleepCount.toInt() != 0xFFFF
        val deepSleepInSeconds = sleepDurationFormat(converted.deepSleepTotal, isOldFormat)
        val remSleepInSeconds = sleepDurationFormat(converted.rapidEyeMovementTotal, isOldFormat)
        val lightSleepInSeconds = sleepDurationFormat(converted.lightSleepTotal, isOldFormat)
        val awakeSleepInSeconds = sleepDurationFormat(converted.wakeDuration, isOldFormat)

        val details = converted.sleepData.map {
                detail ->
            val sleepType = when(detail.sleepType)
            {
                0xF1 -> YuchengSleepType.DEEP
                0xF2 -> YuchengSleepType.LIGHT
                0xF3 -> YuchengSleepType.REM
                0xF4 -> YuchengSleepType.AWAKE
                else -> YuchengSleepType.UNKNOWN
            }
            YuchengSleepDataDetail(
                startTimeStamp = detail.sleepStartTime,
                duration = detail.sleepLen.toLong(),
                type = sleepType
            )
        }
        return YuchengSleepDataEvent(
            startTimeStamp = converted.startTime,
            endTimeStamp = converted.endTime ?: 0,
            deepCount = deepSleepCount,
            lightCount = converted.lightSleepCount.toLong(),
            awakeCount = converted.wakeCount.toLong(),
            deepInSeconds = deepSleepInSeconds.toLong(),
            remInSeconds = remSleepInSeconds.toLong(),
            lightInSeconds = lightSleepInSeconds.toLong(),
            awakeInSeconds = awakeSleepInSeconds.toLong(),
            details = details,
        )
    }

    private fun sleepDurationFormat(duration: Int, isOldFormat: Boolean): Int {
        return duration * (if (isOldFormat) 60 else 1)
    }
}