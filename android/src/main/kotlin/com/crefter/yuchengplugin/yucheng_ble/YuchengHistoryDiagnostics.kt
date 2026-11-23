package com.crefter.yuchengplugin.yucheng_ble

import com.yucheng.ycbtsdk.Constants

internal enum class YuchengHistoryDiagnostics(
    val type: Int,
    val category: String,
    private val keys: List<String>,
) {
    SLEEP(Constants.DATATYPE.Health_HistorySleep, "sleep", listOf(
        "startTime", "endTime", "deepSleepCount", "lightSleepCount", "deepSleepTotal",
        "lightSleepTotal", "rapidEyeMovementTotal", "remTimes", "wakeCount", "wakeDuration"
    )),
    HEALTH(Constants.DATATYPE.Health_HistoryAll, "health", listOf(
        "startTime", "heartValue", "hrvValue", "cvrrValue", "OOValue", "stepValue", "DBPValue",
        "SBPValue", "tempIntValue", "tempFloatValue", "respiratoryRateValue"
    )),
    SPORT(Constants.DATATYPE.Health_HistorySport, "sport", listOf("sportStartTime", "sportEndTime", "sportStep", "sportDistance", "sportCalorie"));

    fun callback(code: Int, rows: List<*>?, session: Long?) {
        val outcome = when {
            code != 0 -> "sdk_error"
            rows == null -> "missing_payload"
            else -> "success"
        }
        YuchengDiagnostics.summary("history_callback", "category=$category outcome=$outcome sdk_code=$code rows=${rows?.size ?: -1}")
        if (code != 0 || rows == null) return
        val rowLimit = if (this == SLEEP) 16 else 2048
        val chunkSize = if (this == SLEEP) 1 else 64
        YuchengDiagnostics.detailed("history_${category}_payload", session, chunkSize) {
            rows.takeLast(rowLimit).mapNotNull { row ->
                val fields = row as? Map<*, *> ?: return@mapNotNull null
                val payload = numericFields(fields, keys).toMutableMap()
                if (this == SLEEP) {
                    val stages = fields["sleepData"] as? List<*>
                    if (stages != null) {
                        payload["stage_count"] = stages.size
                        payload["stages"] = stages.takeLast(1024).mapNotNull { stage ->
                            (stage as? Map<*, *>)?.let { numericFields(it, stageKeys) }
                        }
                    }
                }
                payload
            }
        }
    }

    private fun numericFields(fields: Map<*, *>, keys: List<String>): Map<String, Any> = buildMap {
        for (key in keys) {
            when (val value = fields[key]) {
                is Byte, is Short, is Int, is Long -> put(key, value)
            }
        }
    }

    companion object {
        private val stageKeys = listOf("sleepStartTime", "stime", "sleepLen", "sleepLong", "sleepType")
    }
}
