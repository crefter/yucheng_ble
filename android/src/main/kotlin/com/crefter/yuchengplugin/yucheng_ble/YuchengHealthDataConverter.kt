package com.crefter.yuchengplugin.yucheng_ble

import YuchengHealthData
import YuchengSleepData
import YuchengSleepDataDetail
import com.google.gson.Gson

private class AllDataBean(
    val heartValue: Int, // heart rate value
    val hrvValue: Int, // HRV
    val cvrrValue: Int ,// CVRR
    val OOValue: Int, // oxygen value
    val stepValue: Int, // number of steps
    val DBPValue: Int, // diastolic pressure
    val tempIntValue: Int, // integer part of temperature
    val tempFloatValue: Int, // decimal part of temperature
    val startTime: Long, // starttimestamp
    val SBPValue: Int, // systolic blood pressure
    val respiratoryRateValue: Int, // respiratory rate value
    val bodyFatIntValue: Int, // body fat integer part
    val bodyFatFloatValue: Int, // body fat decimal part
    val bloodSugarValue: Int // blood sugar*10 value
)

class YuchengHealthDataConverter(private val gson: Gson) {
    fun convert(healthDataBean: Any?): YuchengHealthData {
        val converted = gson.fromJson(healthDataBean.toString(), AllDataBean::class.java)
        return YuchengHealthData(
            heartValue = converted.heartValue.toLong(),
            hrvValue = converted.hrvValue.toLong(),
            cvrrValue = converted.cvrrValue.toLong(),
            OOValue = converted.OOValue.toLong(),
            stepValue = converted.stepValue.toLong(),
            DBPValue = converted.DBPValue.toLong(),
            tempIntValue = converted.tempIntValue.toLong(),
            tempFloatValue = converted.tempFloatValue.toLong(),
            startTimestamp = converted.startTime.toLong(),
            SBPValue = converted.SBPValue.toLong(),
            respiratoryRateValue = converted.respiratoryRateValue.toLong(),
            bodyFatIntValue = converted.bodyFatIntValue.toLong(),
            bodyFatFloatValue = converted.bodyFatFloatValue.toLong(),
            bloodSugarValue = converted.bloodSugarValue.toLong(),
        )
    }
}