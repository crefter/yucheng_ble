package com.crefter.yuchengplugin.yucheng_ble


import YuchengDevice
import YuchengDeviceCompleteEvent
import YuchengDeviceDataEvent
import YuchengDeviceEvent
import YuchengDeviceStateEvent
import YuchengDeviceStateTimeOutEvent
import YuchengDeviceTimeOutEvent
import YuchengHealthData
import YuchengHealthDataEvent
import YuchengHealthEvent
import YuchengHealthTimeOutEvent
import YuchengHostApi
import YuchengSleepData
import YuchengSleepDataEvent
import YuchengSleepEvent
import YuchengSleepHealthData
import YuchengSleepHealthDataEvent
import YuchengSleepHealthErrorEvent
import YuchengSleepHealthEvent
import YuchengSleepHealthTimeOutEvent
import YuchengSleepTimeOutEvent
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import com.yucheng.ycbtsdk.Constants
import com.yucheng.ycbtsdk.YCBTClient
import com.yucheng.ycbtsdk.response.BleScanResponse
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset


private const val SCAN_PERIOD: Int = 15
private const val TIME_TO_TIMEOUT: Long = 15

class YuchengApiImpl(
    private val onDevice: (device: YuchengDeviceEvent) -> Unit,
    private val onSleepData: (sleepData: YuchengSleepEvent) -> Unit,
    private val onHealthData: (healthData: YuchengHealthEvent) -> Unit,
    private val onSleepHealthData: (sleepHealthEvent: YuchengSleepHealthEvent) -> Unit,
    private val onState: (state: YuchengDeviceStateEvent) -> Unit,
    private val sleepDataConverter: YuchengSleepDataConverter,
    private val healthDataConverter: YuchengHealthDataConverter,
) : YuchengHostApi {

    private var index: Long = 0
    private var selectedDevice: YuchengDevice? = null

    @OptIn(DelicateCoroutinesApi::class)
    override fun startScanDevices(
        scanTimeInSeconds: Double?,
        callback: (Result<List<YuchengDevice>>) -> Unit
    ) {
        if (YCBTClient.isScaning()) {
            YCBTClient.stopScanBle();
        }
        val devices: MutableList<YuchengDevice> = mutableListOf()
        val completer = CompletableDeferred<List<YuchengDevice>>()
        try {
            Log.d(YuchengBlePlugin.PLUGIN_TAG, "Start scan")
            YCBTClient.startScanBle(BleScanResponse { _, device ->
                if (device == null) {
                    onDevice(YuchengDeviceCompleteEvent(completed = true))
                    if (!completer.isCompleted) completer.complete(devices)
                    Log.d(YuchengBlePlugin.PLUGIN_TAG, "End scan")
                } else {
                    val ycDevice =
                        YuchengDevice(index++, device.deviceName, device.deviceMac, false)
                    devices.add(ycDevice)
                    Log.d(YuchengBlePlugin.PLUGIN_TAG, "name: " + device.deviceName)
                    Log.d(
                        YuchengBlePlugin.PLUGIN_TAG,
                        "address: " + device.deviceMac
                    )
                    onDevice(
                        YuchengDeviceDataEvent(
                            ycDevice.index,
                            ycDevice.uuid,
                            false,
                            ycDevice.deviceName,
                        ),
                    )
                }
            }, scanTimeInSeconds?.toInt() ?: SCAN_PERIOD)
        } catch (e: Exception) {
            Log.e(START_SCAN, e.toString())
            if (!completer.isCompleted) completer.completeExceptionally(e)
            onDevice(YuchengDeviceCompleteEvent(completed = false))
        }
        GlobalScope.launch {
            try {
                callback(Result.success(completer.await()))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }

        GlobalScope.launch {
            delay(1000 * (TIME_TO_TIMEOUT + 5))
            if (!completer.isCompleted) {
                if (devices.isEmpty()) {
                    onDevice(YuchengDeviceTimeOutEvent(isTimeout = true))
                } else {
                    for (device in devices) {
                        onDevice(
                            YuchengDeviceDataEvent(
                                device.index,
                                device.uuid,
                                device.isReconnected,
                                device.deviceName,
                            ),
                        )
                    }
                    onDevice(YuchengDeviceTimeOutEvent(isTimeout = true))
                }
                completer.complete(devices)
            }
        }
    }

    override fun isDeviceConnected(device: YuchengDevice?, callback: (Result<Boolean>) -> Unit) {
        Log.d(IS_DEVICE_CONNECTED, "Start isDeviceConnected")
        try {
            if (device == null) {
                try {
                    val isCurrentConnected =
                        YCBTClient.connectState() == Constants.BLEState.ReadWriteOK
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
                YCBTClient.connectState() == Constants.BLEState.ReadWriteOK && selectedDevice?.uuid == device.uuid
            return isConnected
        } catch (_: Exception) {
            false
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun connect(device: YuchengDevice, callback: (Result<Boolean>) -> Unit) {
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Start connect")
        val macAddress = device.uuid
        selectedDevice = device
        val completer = CompletableDeferred<Boolean>()
        YCBTClient.connectBle(macAddress) { code ->
            if (code == 0) {
                Log.d("AAAAAAAAAAAAAAAAA", code.toString())
                val isConnected = YCBTClient.connectState() == Constants.BLEState.ReadWriteOK
                if (!completer.isCompleted) completer.complete(isConnected)
            }
        }
        GlobalScope.launch {
            callback(Result.success(completer.await()))
        }
        GlobalScope.launch {
            delay(1000 * (TIME_TO_TIMEOUT + 10))
            if (!completer.isCompleted) {
                onState(YuchengDeviceStateTimeOutEvent(isTimeout = true))
                completer.complete(false)
            }
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun reconnect(callback: (Result<Boolean>) -> Unit) {
        val completer = CompletableDeferred<Boolean>()
        try {
            YCBTClient.reconnectBle { code ->
                Log.e("RECONNECT BLE", "CODE = $code")
                if (code == 0) {
                    val isConnected = YCBTClient.connectState() == Constants.BLEState.ReadWriteOK
                    val macAddress = YCBTClient.getBindDeviceMac()
                    val deviceName = YCBTClient.getBindDeviceName()
                    val ycDevice =
                        YuchengDevice(index++, deviceName, macAddress, true)
                    selectedDevice = ycDevice
                    onDevice(
                        YuchengDeviceDataEvent(
                            ycDevice.index,
                            ycDevice.uuid,
                            ycDevice.isReconnected,
                            ycDevice.deviceName,
                        )
                    )
                    if (!completer.isCompleted) completer.complete(isConnected)
                }
            }
        } catch (e: Exception) {
            if (!completer.isCompleted) completer.completeExceptionally(e)
        }
        GlobalScope.launch {
            try {
                callback(Result.success(completer.await()))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
        GlobalScope.launch {
            delay(1000 * TIME_TO_TIMEOUT * 2)
            if (!completer.isCompleted) {
                onState(YuchengDeviceStateTimeOutEvent(isTimeout = true))
                completer.complete(false)
            }
        }
    }

    override fun disconnect(callback: (Result<Unit>) -> Unit) {
        try {
            YCBTClient.disconnectBle()
            callback(Result.success(Unit))
        } catch (e: Exception) {
            Log.e(DISCONNECT, e.toString())
            callback(Result.failure(e))
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    private suspend fun getSleepData(
        skipHandler: Boolean = false,
        startTimestamp: Long,
        endTimestamp: Long,
    ): List<YuchengSleepData> {
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Get sleep data")
        if (YCBTClient.connectState() != Constants.BLEState.ReadWriteOK) {
            return listOf()
        }
        val sleepDataCompleter = CompletableDeferred<List<YuchengSleepData>>()
        val sleepDataList: MutableList<YuchengSleepData> = mutableListOf()
        try {
            YCBTClient.healthHistoryData(
                Constants.DATATYPE.Health_HistorySleep
            ) { code, ratio, data ->
                if (data != null) {
                    val sleepData = data["data"] as List<*>? ?: return@healthHistoryData
                    val mappedSleep = sleepData.map {
                        val yuchengSleepData = sleepDataConverter.convert(it)
                        return@map yuchengSleepData
                    }.filter {
                        val isInRange =
                            it.startTimeStamp >= startTimestamp && it.endTimeStamp <= endTimestamp
                        return@filter isInRange
                    }
                    sleepDataList.addAll(mappedSleep)
                    if (!skipHandler) {
                        for (sleep in sleepDataList) {
                            val ycDataEvent = YuchengSleepDataEvent(sleep)
                            onSleepData(ycDataEvent)
                        }
                    }
                    Log.d("SLEEP DATA CONVERTED", mappedSleep.toString())
                } else {
                    Log.e("NO SLEEP DATA", "NO SLEEP DATA")
                }
                Log.d("SLEEP CODE", code.toString())
                Log.d("SLEEP RATIO", ratio.toString())
                if (!sleepDataCompleter.isCompleted) {
                    sleepDataCompleter.complete(sleepDataList)
                }
            }
        } catch (e: Exception) {
            Log.e(GET_SLEEP_DATA, e.toString())
            sleepDataCompleter.completeExceptionally(e)
        }

        GlobalScope.launch {
            delay(1000 * TIME_TO_TIMEOUT)
            if (!sleepDataCompleter.isCompleted) {
                if (!skipHandler) {
                    for (sleep in sleepDataList) {
                        val ycDataEvent = YuchengSleepDataEvent(sleep)
                        onSleepData(ycDataEvent)
                    }
                }
                sleepDataCompleter.complete(sleepDataList)
                onSleepData(YuchengSleepTimeOutEvent(isTimeout = true))
            }
        }

        try {
            val sleepData = sleepDataCompleter.await()
            return sleepData
        } catch (e: Exception) {
            Log.e("GET SLEEP DATA ERROR", e.toString())
            throw e
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
                val start: Long =
                    startTimestamp ?: default.start
                val end: Long = endTimestamp ?: default.end
                val sleepData = getSleepData(startTimestamp = start, endTimestamp = end)
                callback(Result.success(sleepData))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun getCurrentConnectedDevice(callback: (Result<YuchengDevice?>) -> Unit) {
        try {
            if (selectedDevice != null) {
                callback(Result.success(selectedDevice))
                return
            }
            val macAddress = YCBTClient.getBindDeviceMac()
            val deviceName = YCBTClient.getBindDeviceName()
            val ycDevice =
                YuchengDevice(index++, deviceName, macAddress, false)
            selectedDevice = ycDevice
            callback(Result.success(ycDevice))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    private suspend fun getHealthData(
        skipHandler: Boolean = false,
        startTimestamp: Long,
        endTimestamp: Long,
    ): List<YuchengHealthData> {
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Get health data")
        if (YCBTClient.connectState() != Constants.BLEState.ReadWriteOK) {
            return listOf()
        }
        val healthDataCompleter = CompletableDeferred<List<YuchengHealthData>>()
        val healthDataList: MutableList<YuchengHealthData> = mutableListOf()
        try {
            YCBTClient.healthHistoryData(
                Constants.DATATYPE.Health_HistoryAll
            ) { code, ratio, data ->
                if (data != null) {
                    val healthData = data["data"] as List<*>? ?: return@healthHistoryData
                    val healthDatas = healthData.map {
                        val yuchengHealthData = healthDataConverter.convert(it)
                        return@map yuchengHealthData
                    }.filter {
                        it.startTimestamp >= startTimestamp && it.startTimestamp <= endTimestamp
                    }
                    healthDataList.addAll(healthDatas)
                    if (!skipHandler) {
                        for (health in healthDataList) {
                            val ycDataEvent = YuchengHealthDataEvent(health)
                            onHealthData(ycDataEvent)
                        }
                    }
                    Log.d("HEALTH DATA CONVERTED", healthDatas.toString())
                } else {
                    Log.e("NO HEALTH DATA", "NO HEALTH DATA")
                }
                Log.d("HEALTH CODE", code.toString())
                Log.d("HEALTH RATIO", ratio.toString())
                if (!healthDataCompleter.isCompleted) {
                    healthDataCompleter.complete(healthDataList)
                }
            }
        } catch (e: Exception) {
            Log.e(GET_HEALTH_DATA, e.toString())
            healthDataCompleter.completeExceptionally(e)
        }

        GlobalScope.launch {
            delay(1000 * TIME_TO_TIMEOUT)
            if (!healthDataCompleter.isCompleted) {
                if (!skipHandler) {
                    for (health in healthDataList) {
                        val ycDataEvent = YuchengHealthDataEvent(health)
                        onHealthData(ycDataEvent)
                    }
                }
                healthDataCompleter.complete(healthDataList)
                onHealthData(YuchengHealthTimeOutEvent(isTimeout = true))
            }
        }

        try {
            val healthData = healthDataCompleter.await()
            return healthData
        } catch (e: Exception) {
            Log.e("GET HEALTH DATA ERROR", e.toString())
            throw e
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    @OptIn(DelicateCoroutinesApi::class)
    override fun getHealthData(
        startTimestamp: Long?,
        endTimestamp: Long?, callback: (Result<List<YuchengHealthData>>) -> Unit,
    ) {
        GlobalScope.launch {
            try {
                val default = StartEndTimestamp.default()
                val start: Long =
                    startTimestamp ?: default.start
                val end: Long = endTimestamp ?: default.end
                val healthData = getHealthData(startTimestamp = start, endTimestamp = end)
                callback(Result.success(healthData))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    @OptIn(DelicateCoroutinesApi::class)
    override fun getSleepHealthData(
        startTimestamp: Long?,
        endTimestamp: Long?, callback: (Result<YuchengSleepHealthData>) -> Unit,
    ) {
        Log.d(GET_SLEEP_HEALTH_DATA, "Start get sleep health data")
        val empty = YuchengSleepHealthData(listOf(), listOf())
        if (YCBTClient.connectState() != Constants.BLEState.ReadWriteOK) {
            callback(Result.success(empty))
            return
        }
        val sleepHealthDataCompleter = CompletableDeferred<YuchengSleepHealthData>()
        GlobalScope.launch {
            try {
                val default = StartEndTimestamp.default()
                val start: Long =
                    startTimestamp ?: default.start
                val end: Long = endTimestamp ?: default.end
                val sleepData =
                    getSleepData(skipHandler = true, startTimestamp = start, endTimestamp = end)
                val healthData =
                    getHealthData(skipHandler = true, startTimestamp = start, endTimestamp = end)
                val sleepHealthData = YuchengSleepHealthData(sleepData, healthData)
                Log.d(GET_SLEEP_HEALTH_DATA, "Sleep Health data = $sleepHealthData")
                if (!sleepHealthDataCompleter.isCompleted) {
                    onSleepHealthData(YuchengSleepHealthDataEvent(sleepHealthData))
                    sleepHealthDataCompleter.complete(sleepHealthData)
                }
            } catch (e: Exception) {
                if (!sleepHealthDataCompleter.isCompleted) {
                    Log.e(GET_SLEEP_HEALTH_DATA, "Sleep Health error = $e")
                    onSleepHealthData(YuchengSleepHealthErrorEvent(error = e.toString()))
                    sleepHealthDataCompleter.completeExceptionally(e)
                }
            }
        }
        GlobalScope.launch {
            delay(1000 * (TIME_TO_TIMEOUT + 1))
            if (!sleepHealthDataCompleter.isCompleted) {
                onSleepHealthData(YuchengSleepHealthDataEvent(empty))
                sleepHealthDataCompleter.complete(empty)
                onSleepHealthData(YuchengSleepHealthTimeOutEvent(isTimeout = true))
            }
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


    companion object {
        private const val YUCHENG_API = "YUCH_API"
        private const val GET_SLEEP_DATA = "$YUCHENG_API GET_SLEEP_DATA"
        private const val GET_HEALTH_DATA = "$YUCHENG_API GET_HEALTH_DAT"
        private const val GET_SLEEP_HEALTH_DATA = "GET_SLEEP_HEALTH_DATA"
        private const val DISCONNECT = "$YUCHENG_API DISCONNECT"
        private const val START_SCAN = "$YUCHENG_API START SCAN"
        private const val IS_DEVICE_CONNECTED = "$YUCHENG_API IS_DEV_CON"
    }
}

private data class StartEndTimestamp(val start: Long, val end: Long) {
    @RequiresApi(Build.VERSION_CODES.O)
    companion object {
        private const val DEFAULT_START_DATE_OFFSET: Long = 8
        fun default(): StartEndTimestamp {
            val startDate =
                Instant.now().atZone(ZoneId.systemDefault()).toLocalDate().atStartOfDay()
            val start: Long = (startDate.minusDays(DEFAULT_START_DATE_OFFSET)
                .toEpochSecond(ZoneOffset.UTC) * 1000).toLong()
            val end: Long = (startDate.plusDays(1).toLocalDate().atStartOfDay()
                .toEpochSecond(ZoneOffset.UTC) * 1000).toLong()
            return StartEndTimestamp(start, end)
        }
    }
}