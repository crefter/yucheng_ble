package com.crefter.yuchengplugin.yucheng_ble.entity

import android.os.Build
import androidx.annotation.RequiresApi
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset

data class StartEndTimestamp(val start: Long, val end: Long) {
    @RequiresApi(Build.VERSION_CODES.O)
    companion object {
        private const val DEFAULT_START_DATE_OFFSET: Long = 8
        fun default(): StartEndTimestamp {
            val startDate =
                Instant.now().atZone(ZoneId.systemDefault()).toLocalDate().atStartOfDay()
            val start: Long = (startDate.minusDays(DEFAULT_START_DATE_OFFSET)
                .toEpochSecond(ZoneOffset.UTC) * 1000)
            val end: Long = (startDate.plusDays(1).toLocalDate().atStartOfDay()
                .toEpochSecond(ZoneOffset.UTC) * 1000)
            return StartEndTimestamp(start, end)
        }
    }
}