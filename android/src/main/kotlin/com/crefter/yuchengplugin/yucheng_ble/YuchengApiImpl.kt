@file:OptIn(ExperimentalTime::class, ExperimentalAtomicApi::class)

package com.crefter.yuchengplugin.yucheng_ble


import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.RequiresApi
import com.crefter.yuchengplugin.yucheng_ble.entity.StartEndTimestamp
import com.crefter.yuchengplugin.yucheng_ble.entity.YuchengAuthToken
import com.crefter.yuchengplugin.yucheng_ble.entity.YuchengFlavor
import com.crefter.yuchengplugin.yucheng_ble.service.YuchengBleService
import com.yucheng.ycbtsdk.Constants
import com.yucheng.ycbtsdk.YCBTClient
import com.yucheng.ycbtsdk.upgrade.DfuCallBack
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import kotlin.concurrent.atomics.ExperimentalAtomicApi
import kotlin.math.roundToLong
import kotlin.time.ExperimentalTime


private const val SCAN_PERIOD: Int = 20
private const val TIME_TO_TIMEOUT: Long = 15
private const val TIME_TO_TIMEOUT_RESET: Long = 30
private const val REAL_MEASUREMENT_TIMEOUT_MILLIS: Long = 90 * 1000

class UserExitedMeasurementException : Exception()
class RealTimeMeasurementFailedException : Exception()
class NoConnectionException : Exception()

class YuchengApiImpl(
    private val onDevice: (device: YuchengDeviceEvent) -> Unit,
    private val onSleepData: (sleepData: YuchengSleepEvent) -> Unit,
    private val onHealthData: (healthData: YuchengHealthEvent) -> Unit,
    private val onAllData: (sleepHealthEvent: YuchengAllEvent) -> Unit,
    private val onState: (state: YuchengDeviceStateEvent) -> Unit,
    private val onUpdate: (event: YuchengUpdateEvent) -> Unit,
    private val sleepDataConverter: YuchengSleepDataConverter,
    private val healthDataConverter: YuchengHealthDataConverter,
    private val sportDataConverter: YuchengSportDataConverter,
    private val assetPathHandler: (String) -> String,
) : YuchengHostApi {

    var activity: Context? = null
    private var deviceToUpdate: YuchengDevice? = null
    private var pathToUpdate: String = ""
    private var errorUpdateCount = 0

    @OptIn(DelicateCoroutinesApi::class)
    override fun startScanDevices(
        scanTimeInSeconds: Double?, callback: (Result<List<YuchengDevice>>) -> Unit
    ) {
        if (YCBTClient.isScaning()) {
            YCBTClient.stopScanBle()
        }
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val scannedDevices = YuchengCore.scanDevices(
                    scanTimeInSeconds?.toLong() ?: SCAN_PERIOD.toLong(),
                    onDevice
                )
                callback(Result.success(scannedDevices.toList()))
            } catch (e: Exception) {
                Log.e(START_SCAN, e.toString())
                callback(Result.failure(e))
                onDevice(YuchengDeviceCompleteEvent(completed = false))
            }
        }
    }

    override fun isDeviceConnected(device: YuchengDevice?, callback: (Result<Boolean>) -> Unit) {
        Log.d(IS_DEVICE_CONNECTED, "Start isDeviceConnected")
        try {
            if (device == null) {
                try {
                    val isCurrentConnected =
                        YuchengCore.isConnected()
                    callback(Result.success(isCurrentConnected))
                } catch (e: Exception) {
                    callback(Result.failure(e))
                }
            } else {
                callback(Result.success(isDeviceConnected(device)))
            }
        } catch (e: Exception) {
            Log.e(IS_DEVICE_CONNECTED, "Exception when is device connected: $e")
            callback(Result.failure(e))
        }
    }

    private fun isDeviceConnected(device: YuchengDevice): Boolean {
        return try {
            val isConnected =
                YuchengCore.isConnected() && YuchengCore.selectedDevice?.uuid == device.uuid
            return isConnected
        } catch (_: Exception) {
            false
        }
    }

    override fun connect(
        device: YuchengDevice, connectTimeInSeconds: Long?, callback: (Result<Boolean>) -> Unit
    ) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val isConnect =
                    YuchengCore.connect(device, connectTimeInSeconds ?: (TIME_TO_TIMEOUT + 10))
                callback(Result.success(isConnect))
            } catch (e: Exception) {
                if (e is TimeoutCancellationException) {
                    Log.d(YUCHENG_API, "CONNECT TIMEOUT")
                    onState(YuchengDeviceStateTimeOutEvent(isTimeout = true))
                }
                callback(Result.success(false))
            }
        }
    }

    override fun reconnect(
        uuid: String?,
        reconnectTimeInSeconds: Long?,
        callback: (Result<Boolean>) -> Unit
    ) {

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val reconnect = YuchengCore.reconnect(
                    uuid = uuid,
                    reconnectTimeInSeconds = reconnectTimeInSeconds ?: (TIME_TO_TIMEOUT * 6),
                    scanPeriod = SCAN_PERIOD,
                    onDevice = onDevice
                )
                Log.e(YUCHENG_API, "RECONNECT DONE: $reconnect")
                val state = YCBTClient.connectState()
                Log.d(YUCHENG_API, "Connect state = $state")
                callback(Result.success(reconnect))
            } catch (e: Exception) {
                Log.e(YUCHENG_API, "RECONNECT EXCEPTION: $e")
                if (e is TimeoutCancellationException) {
                    onState(YuchengDeviceStateTimeOutEvent(isTimeout = true))
                    callback(Result.success(false))
                } else {
                    callback(Result.failure(e))
                }
            }
        }
    }

    override fun disconnect(callback: (Result<Unit>) -> Unit) {
        Log.d(YUCHENG_API, "Start disconnect")
        try {
            YuchengCore.disconnect()
            callback(Result.success(Unit))
        } catch (e: Exception) {
            Log.e(YUCHENG_API, e.toString())
            callback(Result.failure(e))
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    @OptIn(DelicateCoroutinesApi::class)
    override fun getSleepData(
        startTimestamp: Long?,
        endTimestamp: Long?, callback: (Result<List<YuchengSleepData>>) -> Unit,
    ) {
        GlobalScope.launch {
            try {
                val default = StartEndTimestamp.default()
                Log.d(YUCHENG_API, "default start end = $default")
                val start: Long = startTimestamp ?: default.start
                val end: Long = endTimestamp ?: default.end
                Log.d(YUCHENG_API, "result start = $start, end = $end")
                val sleepData = YuchengCore.getSleepData(
                    startTimestamp = start,
                    endTimestamp = end,
                    sleepDataConverter = sleepDataConverter,
                    onSleepData = onSleepData
                )
                callback(Result.success(sleepData))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun getCurrentConnectedDevice(callback: (Result<YuchengDevice?>) -> Unit) {
        try {
            if (YuchengCore.selectedDevice != null) {
                callback(Result.success(YuchengCore.selectedDevice))
                return
            }
            val macAddress = YCBTClient.getBindDeviceMac()
            val deviceName = YCBTClient.getBindDeviceName()
            if (macAddress.isEmpty()) {
                callback(Result.success(null))
                return
            }
            val ycDevice =
                YuchengDevice(YuchengCore.deviceIndex.fetchAndAdd(1), deviceName, macAddress, false)
            YuchengCore.selectedDevice = ycDevice
            callback(Result.success(ycDevice))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    @OptIn(DelicateCoroutinesApi::class)
    override fun getHealthSportData(
        startTimestamp: Long?,
        endTimestamp: Long?, callback: (Result<YuchengHealthSportData>) -> Unit,
    ) {
        Log.d(YUCHENG_API, "Get health sport data")
        GlobalScope.launch {
            try {
                val default = StartEndTimestamp.default()
                Log.d(YUCHENG_API, "default start end = $default")
                val start: Long = startTimestamp ?: default.start
                val end: Long = endTimestamp ?: default.end
                Log.d(YUCHENG_API, "result start = $start, end = $end")
                val healthData = YuchengCore.getHealthSportData(
                    startTimestamp = start,
                    endTimestamp = end,
                    sportDataConverter = sportDataConverter,
                    healthDataConverter = healthDataConverter,
                    onHealthData = onHealthData
                )
                Log.d(YUCHENG_API, "Health sport data success")
                callback(Result.success(healthData))
            } catch (e: Exception) {
                Log.d(YUCHENG_API, "Health sport data failure")
                callback(Result.failure(e))
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    @OptIn(DelicateCoroutinesApi::class)
    override fun getAllData(
        startTimestamp: Long?,
        endTimestamp: Long?, callback: (Result<YuchengAllData>) -> Unit,
    ) {
        Log.d(GET_SLEEP_HEALTH_DATA, "Start get sleep health data")
        val empty = YuchengAllData(listOf(), YuchengHealthSportData(listOf(), listOf()))
        if (!YuchengCore.isConnected()) {
            Log.d(GET_SLEEP_HEALTH_DATA, "No connection")
            callback(Result.failure(NoConnectionException()))
        }
        val sleepHealthDataCompleter = CompletableDeferred<YuchengAllData>()
        GlobalScope.launch {
            try {
                val default = StartEndTimestamp.default()
                val start: Long = startTimestamp ?: default.start
                val end: Long = endTimestamp ?: default.end
                val sleepData =
                    YuchengCore.getSleepData(
                        skipHandler = true,
                        startTimestamp = start,
                        endTimestamp = end,
                        sleepDataConverter = sleepDataConverter,
                        onSleepData = onSleepData
                    )
                val healthData = YuchengCore.getHealthSportData(
                    skipHandler = true, startTimestamp = start,
                    endTimestamp = end,
                    sportDataConverter = sportDataConverter,
                    healthDataConverter = healthDataConverter,
                    onHealthData = onHealthData
                )
                val sleepHealthData = YuchengAllData(sleepData, healthData)
                Log.d(GET_SLEEP_HEALTH_DATA, "Sleep Health data = $sleepHealthData")
                if (!sleepHealthDataCompleter.isCompleted) {
                    onAllData(YuchengAllDataEvent(sleepHealthData))
                    sleepHealthDataCompleter.complete(sleepHealthData)
                }
            } catch (e: Exception) {
                if (!sleepHealthDataCompleter.isCompleted) {
                    Log.e(GET_SLEEP_HEALTH_DATA, "Sleep Health error = $e")
                    onAllData(YuchengAllErrorEvent(error = e.toString()))
                    sleepHealthDataCompleter.completeExceptionally(e)
                }
            }
        }
        GlobalScope.launch {
            delay(1000 * (TIME_TO_TIMEOUT + 5))
            if (sleepHealthDataCompleter.isCompleted) return@launch
            onAllData(YuchengAllDataEvent(empty))
            sleepHealthDataCompleter.complete(empty)
            onAllData(YuchengAllTimeOutEvent(isTimeout = true))
        }

        GlobalScope.launch {
            try {
                val sleepHealthData = sleepHealthDataCompleter.await()
                callback(Result.success(sleepHealthData))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun getDeviceSettings(callback: (Result<YuchengDeviceSettings?>) -> Unit) {
        Log.d(YUCHENG_API, "Get device settings")
        val completer = CompletableDeferred<YuchengDeviceSettings?>()

        if (!YuchengCore.isConnected()) {
            Log.d(YUCHENG_API, "Device not connected")
            completer.completeExceptionally(NoConnectionException())
        }

        GlobalScope.launch {
            try {
                if (!completer.isCompleted) {
                    YCBTClient.getDeviceInfo { code, _, data ->
                        if (code == 0) {
                            val dataMap = data["data"] as Map<*, *>
                            val batteryLevel = dataMap["deviceBatteryValue"].toString().toLong()
                            val firmwareVersion = dataMap["deviceVersion"].toString()
                            val settings = YuchengDeviceSettings(
                                batteryValue = batteryLevel, firmwareVersion = firmwareVersion
                            )
                            if (!completer.isCompleted) {
                                completer.complete(settings)
                                Log.d(YUCHENG_API, "Settings = $settings")
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                if (!completer.isCompleted) {
                    completer.completeExceptionally(e)
                }
                Log.e(YUCHENG_API, "Get device settings error = $e")
            }
        }

        GlobalScope.launch {
            try {
                val settings = completer.await()
                Log.d(YUCHENG_API, "RESULT DEVICE SETTINGS = $settings")
                callback(Result.success(settings))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }

        GlobalScope.launch {
            delay(1000 * TIME_TO_TIMEOUT)
            if (completer.isCompleted) return@launch
            completer.complete(null)
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    private suspend fun deleteData(healthType: Int): Boolean {
        Log.d(YUCHENG_API, "Delete sleep data")
        val completer = CompletableDeferred<Boolean>()

        if (!YuchengCore.isConnected()) {
            Log.d(YUCHENG_API, "Device not connected")
            completer.complete(false)
        }

        try {
            YCBTClient.deleteHealthHistoryData(healthType) { code, _, _ ->
                if (!completer.isCompleted) {
                    completer.complete(code == 0)
                }
            }
        } catch (e: Exception) {
            if (!completer.isCompleted) {
                completer.completeExceptionally(e)
            }
            Log.e(YUCHENG_API, "Delete data error = $e")
        }

        try {
            val result = completer.await()
            return result
        } catch (e: Exception) {
            throw e
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun deleteSleepData(
        callback: (Result<Boolean>) -> Unit
    ) {
        GlobalScope.launch {
            try {
                val isDeleted = deleteData(Constants.DATATYPE.Health_DeleteSleep)
                callback(Result.success(isDeleted))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun deleteHealthSportData(
        callback: (Result<Boolean>) -> Unit
    ) {
        GlobalScope.launch {
            try {
                val isDeletedHealth = deleteData(Constants.DATATYPE.Health_DeleteAll)
                val isDeletedSport = deleteData(Constants.DATATYPE.Health_DeleteSport)
                val isDeleted = isDeletedHealth && isDeletedSport
                callback(Result.success(isDeleted))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun deleteAllData(
        callback: (Result<Boolean>) -> Unit
    ) {
        GlobalScope.launch {
            try {
                val isSleepDeleted = deleteData(Constants.DATATYPE.Health_DeleteSleep)
                val isHealthDeleted = deleteData(Constants.DATATYPE.Health_DeleteAll)
                val isDeleted = isSleepDeleted && isHealthDeleted
                callback(Result.success(isDeleted))
                if (isDeleted) {
                    onAllData(
                        YuchengAllDataEvent(
                            YuchengAllData(
                                listOf(),
                                YuchengHealthSportData(listOf(), listOf()),
                            )
                        )
                    )
                }
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun resetToFactory(callback: (Result<Boolean>) -> Unit) {
        Log.d(YUCHENG_API, "Reset to factory")
        val completer = CompletableDeferred<Boolean>()

        if (!YuchengCore.isConnected()) {
            Log.d(YUCHENG_API, "Device not connected")
            completer.complete(false)
        }

        try {
            YCBTClient.settingRestoreFactory { code, _, _ ->
                if (!completer.isCompleted) {
                    completer.complete(code == 0)
                }
            }
        } catch (e: Exception) {
            if (!completer.isCompleted) {
                completer.completeExceptionally(e)
            }
            Log.e(YUCHENG_API, "Reset to factory error = $e")
        }

        GlobalScope.launch {
            try {
                val result = completer.await()
                callback(Result.success(result))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }

        GlobalScope.launch {
            delay(1000 * TIME_TO_TIMEOUT_RESET)
            if (completer.isCompleted) return@launch
            completer.complete(false)
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    @OptIn(DelicateCoroutinesApi::class)
    override fun updateFirmware(
        device: YuchengDevice, pathToFile: String, callback: (Result<Boolean>) -> Unit
    ) {
        if (activity == null) {
            Log.e(UPDATE_FIRMWARE, "Activity is null")
            callback(Result.failure(Exception("Activity is null")))
            return
        }
        Log.d(UPDATE_FIRMWARE, "activity = $activity")
        val path = assetPathHandler(pathToFile)
        pathToUpdate = path
        Log.d(UPDATE_FIRMWARE, "Key = $path")
        val macAddress = device.uuid
        val deviceName = device.deviceName
        deviceToUpdate = YuchengDevice(
            device.index, device.deviceName, device.uuid, device.isReconnected
        )
        Log.d(UPDATE_FIRMWARE, "MacAddress = $macAddress, DeviceName = $deviceName")
        upgrade(callback)
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun upgrade(callback: (Result<Boolean>) -> Unit) {
        var isCompleted = false
        if (activity == null) {
            Log.e(UPDATE_FIRMWARE, "Activity is null")
            callback(Result.failure(Exception("Activity is null")))
            return
        }
        if (pathToUpdate.isEmpty()) {
            Log.e(UPDATE_FIRMWARE, "Path is empty")
            callback(Result.failure(Exception("Path is empty")))
            return
        }
        if (deviceToUpdate == null) {
            Log.e(UPDATE_FIRMWARE, "Device is null")
            callback(Result.failure(Exception("Device is null")))
            return
        }

        YCBTClient.setOta(true)
        val timestamp =
            Instant.now().atZone(ZoneId.systemDefault()).toLocalDateTime().toEpochSecond(
                ZoneOffset.UTC
            )
        onUpdate(YuchengUpdateStartEvent(timestamp))
        YCBTClient.upgradeFirmware(
            activity, deviceToUpdate!!.uuid, deviceToUpdate!!.deviceName, pathToUpdate,
            object : DfuCallBack {
                override fun progress(p0: Int) {
                    Log.d(UPDATE_FIRMWARE, "Progress = $p0")
                    onUpdate(YuchengUpdateProgressEvent(p0 / 10000.0))
                }

                @RequiresApi(Build.VERSION_CODES.O)
                override fun success() {
                    Log.d(UPDATE_FIRMWARE, "Success")
                    YCBTClient.setOta(false)
                    Handler(Looper.getMainLooper()).postDelayed({
                        YCBTClient.disconnectBle()
                    }, 1500)
                    errorUpdateCount = 0
                    isCompleted = true
                    val date = Instant.now().atZone(ZoneId.systemDefault()).toLocalDateTime()
                        .toEpochSecond(
                            ZoneOffset.UTC
                        )
                    onUpdate(YuchengUpdateCompleteEvent(date))
                    callback(Result.success(true))
                }

                override fun failed(p0: String?) {
                    Log.d(UPDATE_FIRMWARE, "Failed = $p0")
                    if (p0?.contains("Data verification failure") == true) {
                        onUpdate(YuchengUpdateErrorEvent(p0))
                        callback(Result.failure(Exception(p0)))
                        isCompleted = true
                        errorUpdateCount = 0
                        return
                    }
                    errorUpdateCount++
                    if (!isCompleted && errorUpdateCount > 3) {
                        onUpdate(YuchengUpdateErrorEvent(p0 ?: ""))
                        callback(Result.failure(Exception(p0)))
                        isCompleted = true
                        errorUpdateCount = 0
                    }
                }

                override fun disconnect() {
                    Log.d(UPDATE_FIRMWARE, "Disconnect")
                }

                override fun onNeedReconnect(p0: String?, p1: Boolean) {
                    Log.d(UPDATE_FIRMWARE, "ON NEED RECONNECT")
                }

                override fun connecting() {
                    Log.d(UPDATE_FIRMWARE, "Connecting")
                }

                override fun connected() {
                    Log.d(UPDATE_FIRMWARE, "Connected")
                }

                override fun latest() {
                    Log.d(UPDATE_FIRMWARE, "Latest")
                    errorUpdateCount = 0
                }

                override fun error(p0: String?) {
                    Log.d(UPDATE_FIRMWARE, "Error = $p0")
                    if (!isCompleted) {
                        onUpdate(YuchengUpdateErrorEvent(p0 ?: ""))
                        callback(Result.failure(Exception(p0)))
                        isCompleted = true
                    }
                }
            },
        )
        YCBTClient.watchUiUpgrade(pathToUpdate) { code, ratio, map ->
            Log.d(UPDATE_FIRMWARE, "Map = $map")
            Log.d(UPDATE_FIRMWARE, "Code = $code")
            Log.d(UPDATE_FIRMWARE, "Ratio = $ratio")
            if (map != null) {
                val progress = map["progress"]
                val data = map["data"]
                Log.d(UPDATE_FIRMWARE, "Progress = $progress")
                Log.d(UPDATE_FIRMWARE, "Data = $data")
                if (progress != null) {
                    Log.d(UPDATE_FIRMWARE, "Progress = $progress")
                } else if (data != null) {
                    if (data == 0) {
                        Log.d(UPDATE_FIRMWARE, "Success")
                        if (!isCompleted) {
                            callback(Result.success(true))
                            isCompleted = true
                        }
                    } else {
                        Log.d(UPDATE_FIRMWARE, "Failed")
                        if (!isCompleted) {
                            callback(Result.success(false))
                            isCompleted = true
                        }
                    }
                }
            }
        }
    }

    override fun getHealthMonitorInterval(callback: (Result<Long?>) -> Unit) {
        callback(Result.success(null))
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun setHealthMonitorInterval(
        interval: Long, callback: (Result<Boolean>) -> Unit
    ) {
        Log.d(YUCHENG_API, "Start set health monitoring interval")
        val heartCompleter = CompletableDeferred<Boolean>()
        val bloodCompleter = CompletableDeferred<Boolean>()
        try {
            YCBTClient.settingHeartMonitor(0x01, interval.toInt()) { code, _, _ ->
                if (heartCompleter.isCompleted) return@settingHeartMonitor
                if (code == 0) {
                    heartCompleter.complete(true)
                } else {
                    heartCompleter.complete(false)
                }
            }
            YCBTClient.settingBloodOxygenModeMonitor(true, interval.toInt()) { code, _, _ ->
                if (bloodCompleter.isCompleted) return@settingBloodOxygenModeMonitor
                if (code == 0) {
                    bloodCompleter.complete(true)
                } else {
                    bloodCompleter.complete(false)
                }
            }
        } catch (e: Exception) {
            if (!heartCompleter.isCompleted) {
                heartCompleter.completeExceptionally(e)
            } else if (!bloodCompleter.isCompleted) {
                bloodCompleter.completeExceptionally(e)
            }
        }

        GlobalScope.launch {
            try {
                val heartResult = heartCompleter.await()
                val bloodResult = bloodCompleter.await()
                Log.d(YUCHENG_API, "Set health monitoring interval successful")
                callback(Result.success(heartResult && bloodResult))
            } catch (e: Exception) {
                Log.d(YUCHENG_API, "Set health monitoring interval failed")
                callback(Result.failure(e))
            }
        }
    }

    private data class MeanBloodPressure(
        val sbp: Long, val dbp: Long
    )

    @RequiresApi(Build.VERSION_CODES.O)
    @OptIn(DelicateCoroutinesApi::class)
    override fun getRealTimeHealthRecord(callback: (Result<YuchengHealthSportData>) -> Unit) {
        Log.d(YUCHENG_API, "START getRealTimeHealthRecord")
        val heartRates: MutableList<Long> = mutableListOf()
        val bloodPressures: MutableList<MeanBloodPressure> = mutableListOf()
        val bloodOxygens: MutableList<Long> = mutableListOf()
        var heartRate: Long = 0
        var bloodPressure = MeanBloodPressure(sbp = 0, dbp = 0)
        var bloodOxygen: Long = 0
        var steps: Long = 0
        var calories: Long = 0
        var distance: Long = 0

        val heartRateCompleter = CompletableDeferred<Long>()
        val bloodPressureCompleter = CompletableDeferred<MeanBloodPressure>()
        val bloodOxygenCompleter = CompletableDeferred<Long>()
        val sportCompleter = CompletableDeferred<Boolean>()

        val completer = CompletableDeferred<Boolean>()

        GlobalScope.launch {
            try {
                YCBTClient.deviceToApp { code, data ->
                    Log.d(YUCHENG_API, "DEVICETOAPP code = $code data = $data")
                    if (code == 0 && data != null) {
                        val dataType = data["dataType"] as Int
                        Log.d(YUCHENG_API, "DEVICETOAPP dataType = $dataType")
                        if (dataType == Constants.DATATYPE.DeviceMeasurementResult) {
                            val datas = data["datas"] as ByteArray
                            Log.d(YUCHENG_API, "DEVICETOAPP datas = $datas")
                            if (datas.isNotEmpty()) {
                                val type = datas[0].toInt()
                                val result = datas[1].toInt()
                                Log.d(YUCHENG_API, "DEVICETOAPP type = $type")
                                Log.d(YUCHENG_API, "DEVICETOAPP result = $result")
                                if (result == 1) {
                                    when (type) {
                                        REAL_HEART_RATE_TYPE -> {
                                            val sum =
                                                heartRates.reduce { prev, next -> prev + next }
                                            var count = heartRates.count()
                                            count = if (count < 1) 1 else count
                                            val mean = sum / count
                                            Log.d(YUCHENG_API, "Heart rate mean: $mean")
                                            heartRateCompleter.complete(mean)
                                        }

                                        REAL_BLOOD_OXYGEN_TYPE -> {
                                            val sum =
                                                bloodOxygens.reduce { prev, next -> prev + next }
                                            var count = bloodOxygens.count()
                                            count = if (count < 1) 1 else count
                                            val mean = sum / count
                                            Log.d(YUCHENG_API, "Blood oxygen mean: $mean")
                                            bloodOxygenCompleter.complete(mean)
                                        }

                                        REAL_BLOOD_PRESSURE_TYPE -> {
                                            var count = bloodPressures.count()
                                            count = if (count < 1) 1 else count
                                            val sumDbp = bloodPressures.sumOf { item -> item.dbp }
                                            val meanDbp = sumDbp / count
                                            val sumSbp = bloodPressures.sumOf { item -> item.sbp }
                                            val meanSbp = sumSbp / count
                                            Log.d(YUCHENG_API, "Blood pressure SBP mean: $meanSbp")
                                            Log.d(YUCHENG_API, "Blood pressure DBP mean: $meanDbp")
                                            bloodPressureCompleter.complete(
                                                MeanBloodPressure(
                                                    sbp = meanSbp, dbp = meanDbp
                                                )
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                YCBTClient.appRegisterRealDataCallBack { type, data ->
                    if (data != null) {
                        if (!sportCompleter.isCompleted && type == Constants.DATATYPE.Real_UploadSport) {
                            steps = (data["sportStep"] as Int).toLong()
                            calories = (data["sportCalorie"] as Int).toLong()
                            distance = (data["sportDistance"] as Int).toLong()
                            Log.d(
                                YUCHENG_API,
                                "Sport data: steps = $steps, calories = $calories, distance = $distance"
                            )
                            sportCompleter.complete(true)
                            completer.complete(true)
                        }
                        if (type == Constants.DATATYPE.Real_UploadHeart) {
                            val value = data["heartValue"] as Int
                            Log.d(YUCHENG_API, "heart rate = $value")
                            heartRates.add(value.toLong())
                        }
                        if (type == Constants.DATATYPE.Real_UploadBloodOxygen) {
                            val value = data["bloodOxygenValue"] as Int
                            Log.d(YUCHENG_API, "blood oxygen = $value")
                            bloodOxygens.add(value.toLong())
                        }
                        if (type == Constants.DATATYPE.Real_UploadBlood) {
                            val dbp = data["bloodDBP"] as Int
                            val sbp = data["bloodSBP"] as Int
                            Log.d(YUCHENG_API, "blood DBP = $dbp")
                            Log.d(YUCHENG_API, "blood SBP = $sbp")
                            bloodPressures.add(
                                MeanBloodPressure(
                                    sbp = sbp.toLong(), dbp = dbp.toLong()
                                )
                            )
                        }
                    }
                }

                YCBTClient.appStartMeasurement(1, REAL_HEART_RATE_TYPE) { _, _, _ ->
                    Log.d(YUCHENG_API, "START HEART RATE MEASURE")
                }
                Log.d(YUCHENG_API, "WAITING HEART RATE")
                heartRate = heartRateCompleter.await()
                Log.d(YUCHENG_API, "HEART RATE = $heartRate")
                YCBTClient.appStartMeasurement(1, REAL_BLOOD_PRESSURE_TYPE) { _, _, _ ->
                    Log.d(YUCHENG_API, "START BLOOD PRESSURE MEASURE")
                }
                Log.d(YUCHENG_API, "WAITING BLOOD PRESSURE")
                bloodPressure = bloodPressureCompleter.await()
                Log.d(YUCHENG_API, "BLOOD PRESSURE = $bloodPressure")

                YCBTClient.appStartMeasurement(1, REAL_BLOOD_OXYGEN_TYPE) { _, _, _ ->
                    Log.d(YUCHENG_API, "START BLOOD OXYGEN MEASURE")
                }
                Log.d(YUCHENG_API, "WAITING BLOOD OXYGEN")
                bloodOxygen = bloodOxygenCompleter.await()
                Log.d(YUCHENG_API, "BLOOD OXYGEN = $bloodOxygen")
                YCBTClient.appRealDataFromDevice(1, 0) { _, _, _ ->
                    Log.d(YUCHENG_API, "START SPORT MEASURE")
                }
                Log.d(YUCHENG_API, "WAITING SPORT")
                sportCompleter.await()
                Log.d(YUCHENG_API, "SPORT COMPLETED")
                if (!completer.isCompleted) completer.complete(true)
            } catch (e: Exception) {
                Log.d(YUCHENG_API, "ERROR = $e")
                if (!completer.isCompleted) {
                    completer.completeExceptionally(e)
                }
            }
        }


        GlobalScope.launch {
            try {
                completer.await()
                val startTimeStamp = Instant.now().toEpochMilli()
                val healthData = YuchengHealthData(
                    heartRate,
                    0,
                    0,
                    bloodOxygen,
                    0,
                    bloodPressure.dbp,
                    0,
                    0,
                    startTimeStamp,
                    bloodPressure.sbp,
                    0,
                    0,
                    0,
                    0
                )
                val sportData = YuchengSportData(
                    startTimeStamp, startTimeStamp, distance, steps, calories
                )
                val healthSportData = YuchengHealthSportData(
                    listOf(healthData), listOf(sportData)
                )
                onHealthData(
                    YuchengHealthDataEvent(
                        healthSportData
                    )
                )
                Log.d(YUCHENG_API, "Health sport data = $healthSportData")
                callback(Result.success(healthSportData))
            } catch (e: Exception) {
                Log.d(YUCHENG_API, "ERROR = $e")
                callback(Result.failure(e))
            }
        }
        GlobalScope.launch {
            delay(1000 * 600)
            if (completer.isCompleted) return@launch

            callback(Result.failure(Exception("Timeout")))
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun startMeasurementBloodOxygen(callback: (Result<Long?>) -> Unit) {
        Log.d(YUCHENG_API, "START getRealTimeBloodOxygen")
        if (!YuchengCore.isConnected()) {
            Log.d(YUCHENG_API, "Device not connected")
            callback(Result.failure(NoConnectionException()))
            return
        }
        val completer = CompletableDeferred<Boolean>()

        GlobalScope.launch {
            try {
                val value = getRealTimeData(
                    measureDataType = REAL_BLOOD_OXYGEN_TYPE,
                    sdkDataType = Constants.DATATYPE.Real_UploadBloodOxygen,
                    onReduce = { values ->
                        val sum = values.reduce { prev, next -> prev + next }.toDouble()
                        var count = values.count()
                        count = if (count < 1) 1 else count
                        val mean = (sum / count).roundToLong()
                        Log.d(YUCHENG_API, "Blood oxygen mean: $mean")
                        return@getRealTimeData mean
                    },
                    convert = { data ->
                        if (data == null) {
                            return@getRealTimeData 0
                        }
                        val value = data["bloodOxygenValue"] as Int
                        Log.d(YUCHENG_API, "blood oxygen = $value")
                        return@getRealTimeData value.toLong()
                    },
                )
                Log.d(YUCHENG_API, "Blood oxygen = $value")
                if (!completer.isCompleted) {
                    callback(Result.success(value))
                    completer.complete(true)
                }
            } catch (e: Exception) {
                Log.d(YUCHENG_API, "ERROR = $e")
                if (!completer.isCompleted) {
                    callback(Result.failure(e))
                    completer.complete(true)
                }
            }
        }
        GlobalScope.launch {
            delay(1000 * 120)
            if (completer.isCompleted) return@launch

            callback(Result.success(null))
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun startMeasurementHeart(callback: (Result<Long?>) -> Unit) {
        Log.d(YUCHENG_API, "START getRealTimeHeart")
        if (!YuchengCore.isConnected()) {
            Log.d(YUCHENG_API, "Device not connected")
            callback(Result.failure(NoConnectionException()))
            return
        }
        val completer = CompletableDeferred<Boolean>()

        GlobalScope.launch {
            try {
                val value = getRealTimeData(
                    measureDataType = REAL_HEART_RATE_TYPE,
                    sdkDataType = Constants.DATATYPE.Real_UploadHeart,
                    onReduce = { values ->
                        val sum = values.reduce { prev, next -> prev + next }.toDouble()
                        var count = values.count()
                        count = if (count < 1) 1 else count
                        val mean = (sum / count).roundToLong()
                        Log.d(YUCHENG_API, "Heart rate mean: $mean")
                        return@getRealTimeData mean
                    },
                    convert = { data ->
                        if (data == null) {
                            return@getRealTimeData 0
                        }
                        val value = data["heartValue"] as Int
                        Log.d(YUCHENG_API, "heart rate = $value")
                        return@getRealTimeData value.toLong()
                    },
                )
                if (!completer.isCompleted) {
                    callback(Result.success(value))
                    completer.complete(true)
                }
            } catch (e: Exception) {
                Log.d(YUCHENG_API, "ERROR = $e")
                if (!completer.isCompleted) {
                    callback(Result.failure(e))
                    completer.complete(true)
                }
            }
        }
        GlobalScope.launch {
            delay(1000 * 120)
            if (completer.isCompleted) return@launch

            callback(Result.success(null))
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun startMeasurementBloodPressure(callback: (Result<RealTimeBloodPressure?>) -> Unit) {
        Log.d(YUCHENG_API, "START getRealTimeBloodPressure")
        if (!YuchengCore.isConnected()) {
            Log.d(YUCHENG_API, "Device not connected")
            callback(Result.failure(NoConnectionException()))
            return
        }
        val completer = CompletableDeferred<Boolean>()

        GlobalScope.launch {
            try {
                val value = getRealTimeData(
                    measureDataType = REAL_BLOOD_PRESSURE_TYPE,
                    sdkDataType = Constants.DATATYPE.Real_UploadBlood,
                    onReduce = { values ->
                        var count = values.count()
                        count = if (count < 1) 1 else count
                        val sumDbp = values.sumOf { item -> item.dbp }.toDouble()
                        val meanDbp = (sumDbp / count).roundToLong()
                        val sumSbp = values.sumOf { item -> item.sbp }.toDouble()
                        val meanSbp = (sumSbp / count).roundToLong()
                        Log.d(YUCHENG_API, "Blood pressure SBP mean: $meanSbp")
                        Log.d(YUCHENG_API, "Blood pressure DBP mean: $meanDbp")
                        return@getRealTimeData MeanBloodPressure(sbp = meanSbp, dbp = meanDbp)
                    },
                    convert = { data ->
                        if (data == null) {
                            return@getRealTimeData MeanBloodPressure(sbp = 0, dbp = 0)
                        }
                        val dbp = data["bloodDBP"] as Int
                        val sbp = data["bloodSBP"] as Int
                        Log.d(YUCHENG_API, "blood DBP = $dbp")
                        Log.d(YUCHENG_API, "blood SBP = $sbp")
                        return@getRealTimeData MeanBloodPressure(
                            sbp = sbp.toLong(), dbp = dbp.toLong()
                        )
                    })
                val result = RealTimeBloodPressure(
                    dbp = value.dbp, sbp = value.sbp
                )
                if (!completer.isCompleted) {
                    callback(Result.success(result))
                    completer.complete(true)
                }
            } catch (e: Exception) {
                Log.d(YUCHENG_API, "ERROR = $e")
                if (!completer.isCompleted) {
                    callback(Result.failure(e))
                    completer.complete(true)
                }
            }
        }
        GlobalScope.launch {
            delay(1000 * 120)
            if (completer.isCompleted) return@launch

            callback(Result.success(null))
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun stopMeasurementBloodOxygen(callback: (Result<Boolean>) -> Unit) {
        Log.d(YUCHENG_API, "START stopMeasurementBloodOxygen")
        GlobalScope.launch {
            try {
                val result = stopMeasurementByType(REAL_BLOOD_OXYGEN_TYPE)
                if (result) {
                    Log.d(YUCHENG_API, "STOPPED stopMeasurementBloodOxygen")
                } else {
                    Log.d(YUCHENG_API, "NOT STOPPED stopMeasurementBloodOxygen")
                }
                callback(Result.success(result))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun stopMeasurementBloodPressure(callback: (Result<Boolean>) -> Unit) {
        Log.d(YUCHENG_API, "START stopMeasurementBloodPressure")
        GlobalScope.launch {
            try {
                val result = stopMeasurementByType(REAL_BLOOD_PRESSURE_TYPE)
                if (result) {
                    Log.d(YUCHENG_API, "STOPPED stopMeasurementBloodPressure")
                } else {
                    Log.d(YUCHENG_API, "NOT STOPPED stopMeasurementBloodPressure")
                }
                callback(Result.success(result))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun stopMeasurementHeart(callback: (Result<Boolean>) -> Unit) {
        Log.d(YUCHENG_API, "START stopMeasurementHeart")
        GlobalScope.launch {
            try {
                val result = stopMeasurementByType(REAL_HEART_RATE_TYPE)
                if (result) {
                    Log.d(YUCHENG_API, "STOPPED stopMeasurementHeart")
                } else {
                    Log.d(YUCHENG_API, "NOT STOPPED stopMeasurementHeart")
                }
                callback(Result.success(result))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    private suspend fun stopMeasurementByType(type: Int): Boolean {
        val completed = CompletableDeferred<Boolean>()

        YCBTClient.appStartMeasurement(0, type) { code, _, _ ->
            Log.d(YUCHENG_API, "STOP MEASURE")
            completed.complete(code == 0)
        }

        return completed.await()
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun calibrateBloodPressure(
        sbp: Long,
        dbp: Long,
        callback: (Result<Boolean>) -> Unit
    ) {
        Log.d(YUCHENG_API, "START calibrateBloodPressure sbp = $sbp dbp = $dbp")
        if (!YuchengCore.isConnected()) {
            Log.d(YUCHENG_API, "Device not connected")
            callback(Result.failure(NoConnectionException()))
            return
        }
        val completed = CompletableDeferred<Boolean>()
        YCBTClient.appBloodCalibration(sbp.toInt(), dbp.toInt()) { code, _, _ ->
            if (completed.isCompleted) return@appBloodCalibration
            val isCompleted = code == 0
            if (isCompleted) {
                Log.d(YUCHENG_API, "Calibration is completed")
            } else {
                Log.d(YUCHENG_API, "Calibration is NOT completed")
            }
            completed.complete(isCompleted)
        }

        GlobalScope.launch {
            try {
                val result = completed.await()
                callback(Result.success(result))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }

        GlobalScope.launch {
            delay(1000 * TIME_TO_TIMEOUT)
            if (completed.isCompleted) return@launch

            callback(Result.failure(Exception("Timeout")))
        }
    }

    override fun turnOnBackgroundService(
        delayInMinutes: Long,
        callback: (Result<Boolean>) -> Unit
    ) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                YuchengCore.storage?.saveServiceOn(true)
                YuchengCore.storage?.saveDelay(delayInMinutes.toInt())
                withContext(Dispatchers.Main) {
                    if (activity != null) {
                        YuchengBleService.restartService(activity!!)
                    }
                    callback(Result.success(true))
                }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) {
                    callback(Result.success(false))
                }
            }
        }
    }

    override fun turnOffBackgroundService(callback: (Result<Boolean>) -> Unit) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                YuchengCore.storage?.saveServiceOn(false)
                if (activity != null) {
                    YuchengBleService.stopService(activity!!)
                }
                withContext(Dispatchers.Main) {
                    callback(Result.success(true))
                }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) {
                    callback(Result.success(false))
                }
            }
        }
    }

    override fun canLaunchBackgroundService(callback: (Result<Boolean>) -> Unit) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val serviceOn = YuchengCore.storage?.readServiceOn() ?: false
                withContext(Dispatchers.Main) {
                    callback(Result.success(serviceOn))
                }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) {
                    callback(Result.success(false))
                }
            }
        }
    }

    override fun setFlavor(
        flavorName: String, callback: (Result<Unit>) -> Unit
    ) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                YuchengCore.storage?.saveFlavor(flavorName)
                withContext(Dispatchers.Main) {
                    callback(Result.success(Unit))
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    callback(Result.failure(e))
                }
            }
        }
    }

    override fun setToken(
        token: YuchengToken?, callback: (Result<Unit>) -> Unit
    ) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val flavorStr = YuchengCore.storage?.readFlavor()
                val flavor = YuchengFlavor.fromString(flavorStr)
                if (token == null) {
                    YuchengCore.tokenStorage?.clear(flavor)
                } else {
                    val ycAuthToken = YuchengAuthToken(
                        accessToken = token.access,
                        refreshToken = token.refresh,
                        issuedAt = kotlin.time.Instant.fromEpochMilliseconds(token.createdAtTimestamp)
                    )
                    YuchengCore.tokenStorage?.saveTokens(
                        ycAuthToken,
                        flavor
                    )
                }
                withContext(Dispatchers.Main) {
                    callback(Result.success(Unit))
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    callback(Result.failure(e))
                }
            }
        }
    }

    override fun getToken(callback: (Result<YuchengToken?>) -> Unit) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val flavorStr = YuchengCore.storage?.readFlavor()
                val flavor = YuchengFlavor.fromString(flavorStr)
                val token = YuchengCore.tokenStorage?.getToken(flavor)
                withContext(Dispatchers.Main) {
                    callback(Result.success(token))
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    callback(Result.failure(e))
                }
            }
        }
    }

    private suspend fun <T> getRealTimeData(
        measureDataType: Int,
        sdkDataType: Int,
        onReduce: (List<T>) -> T,
        convert: (HashMap<*, *>?) -> T,
    ): T {
        val values: MutableList<T> = mutableListOf()
        var meanValue: T
        val valueCompleter = CompletableDeferred<T>()

        try {
            YCBTClient.deviceToApp { code, data ->
                Log.d(YUCHENG_API, "DEVICETOAPP code = $code data = $data")
                if (code == 0 && data != null) {
                    val dataType = data["dataType"] as Int
                    Log.d(YUCHENG_API, "DEVICETOAPP dataType = $dataType")
                    if (dataType == Constants.DATATYPE.DeviceMeasurementResult) {
                        val datas = data["datas"] as ByteArray
                        Log.d(YUCHENG_API, "DEVICETOAPP datas = $datas")
                        if (datas.isNotEmpty()) {
                            val type = datas[0].toInt()
                            val result = datas[1].toInt()
                            Log.d(YUCHENG_API, "DEVICETOAPP type = $type")
                            Log.d(YUCHENG_API, "DEVICETOAPP result = $result")
                            if (result == 0) {
                                Log.d(YUCHENG_API, "result = 0: UserExitedMeasurementException")
                                if (!valueCompleter.isCompleted) valueCompleter.completeExceptionally(
                                    UserExitedMeasurementException()
                                )
                            } else if (result == 2) {
                                Log.d(YUCHENG_API, "result = 2: RealTimeMeasurementFailedException")
                                if (!valueCompleter.isCompleted) valueCompleter.completeExceptionally(
                                    RealTimeMeasurementFailedException()
                                )
                            } else {
                                Log.d(YUCHENG_API, "result = 1: GOOD")
                                if (type == measureDataType) {
                                    val mean = onReduce(values)
                                    Log.d(YUCHENG_API, "Mean value: $mean")
                                    valueCompleter.complete(mean)
                                }
                            }
                        }
                    }
                }
            }
            YCBTClient.appRegisterRealDataCallBack { type, data ->
                if (data != null) {
                    if (type == sdkDataType) {
                        val value = convert(data)
                        Log.d(YUCHENG_API, "value = $value")
                        values.add(value)
                    }
                }
            }
            YCBTClient.appStartMeasurement(1, measureDataType) { _, _, _ ->
                Log.d(YUCHENG_API, "START MEASURE, dataType = $measureDataType")
            }
            Log.d(YUCHENG_API, "WAITING MEASURE")
            meanValue = withTimeout(REAL_MEASUREMENT_TIMEOUT_MILLIS) {
                valueCompleter.await()
            }
            Log.d(YUCHENG_API, "MEAN VALUE = $meanValue")
        } catch (e: Exception) {
            Log.d(YUCHENG_API, "ERROR = $e")
            if (e is TimeoutCancellationException) {
                Log.d(YUCHENG_API, "Timeout!")
                throw RealTimeMeasurementFailedException()
            }
            throw e
        }

        return meanValue
    }

    companion object {
        private const val REAL_BLOOD_OXYGEN_TYPE = 2
        private const val REAL_HEART_RATE_TYPE = 0
        private const val REAL_BLOOD_PRESSURE_TYPE = 1
        private const val YUCHENG_API = "YUCH_API"
        private const val GET_SLEEP_HEALTH_DATA = "${YUCHENG_API} SLEEP_HEALTH"
        private const val START_SCAN = "$YUCHENG_API START SCAN"
        private const val IS_DEVICE_CONNECTED = "$YUCHENG_API IS_DEV_CON"
        private const val UPDATE_FIRMWARE = "$YUCHENG_API UPDATE_FIRM"
    }
}