package com.crefter.yuchengplugin.yucheng_ble

import YuchengSportData
import com.google.gson.Gson

private class YuchengSportBean(
    val sportStartTime: Long,    // start timestamp (seconds)
val  sportEndTime: Long,  // end timestamp (seconds)
    val sportStep: Int,  // number of steps (steps)
    val sportDistance: Int, // distance (meters)
    val sportCalorie: Int, // calories (kcal)
)

class YuchengSportDataConverter(private val gson: Gson) {
    fun convert(sportDataBean: Any?): YuchengSportData {
        val converted = gson.fromJson(sportDataBean.toString(), YuchengSportBean::class.java)
        return YuchengSportData(
            startTimeStamp = converted.sportStartTime,
            endTimeStamp = converted.sportEndTime,
            distance = converted.sportDistance.toLong(),
            steps = converted.sportStep.toLong(),
            calories = converted.sportCalorie.toLong(),
        )
    }
}