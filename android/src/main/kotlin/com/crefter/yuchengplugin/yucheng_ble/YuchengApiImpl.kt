package com.crefter.yuchengplugin.yucheng_ble


import RealTimeBloodPressure
import YuchengAllData
import YuchengAllDataEvent
import YuchengAllErrorEvent
import YuchengAllEvent
import YuchengAllTimeOutEvent
import YuchengDevice
import YuchengDeviceCompleteEvent
import YuchengDeviceDataEvent
import YuchengDeviceEvent
import YuchengDeviceSettings
import YuchengDeviceStateEvent
import YuchengDeviceStateTimeOutEvent
import YuchengDeviceTimeOutEvent
import YuchengHealthData
import YuchengHealthDataEvent
import YuchengHealthEvent
import YuchengHealthSportData
import YuchengHealthTimeOutEvent
import YuchengHostApi
import YuchengSleepData
import YuchengSleepDataEvent
import YuchengSleepEvent
import YuchengSleepTimeOutEvent
import YuchengSportData
import YuchengUpdateCompleteEvent
import YuchengUpdateErrorEvent
import YuchengUpdateEvent
import YuchengUpdateProgressEvent
import YuchengUpdateStartEvent
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.RequiresApi
import com.yucheng.ycbtsdk.Constants
import com.yucheng.ycbtsdk.YCBTClient
import com.yucheng.ycbtsdk.bean.ScanDeviceBean
import com.yucheng.ycbtsdk.upgrade.DfuCallBack
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import kotlin.math.roundToLong


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

    private var index: Long = 0
    private var selectedDevice: YuchengDevice? = null
    var activity: Context? = null
    private var deviceToUpdate: YuchengDevice? = null
    private var pathToUpdate: String = ""
    private var errorUpdateCount = 0
    private var scannedDevices = mutableSetOf<ScanDeviceBean>()

    @OptIn(DelicateCoroutinesApi::class)
    override fun startScanDevices(
        scanTimeInSeconds: Double?, callback: (Result<List<YuchengDevice>>) -> Unit
    ) {
        if (YCBTClient.isScaning()) {
            YCBTClient.stopScanBle()
        }
        val devices: MutableList<YuchengDevice> = mutableListOf()
        val completer = CompletableDeferred<List<YuchengDevice>>()
        try {
            Log.d(YuchengBlePlugin.PLUGIN_TAG, "Start scan")
            YCBTClient.startScanBle( { _, device ->
                if (device == null) {
                    onDevice(YuchengDeviceCompleteEvent(completed = true))
                    if (!completer.isCompleted) completer.complete(devices)
                    Log.d(YuchengBlePlugin.PLUGIN_TAG, "End scan")
                } else {
                    scannedDevices.add(device)
                    val ycDevice =
                        YuchengDevice(index++, device.deviceName, device.deviceMac, false)
                    devices.add(ycDevice)
                    Log.d(YuchengBlePlugin.PLUGIN_TAG, "name: " + device.deviceName)
                    Log.d(
                        YuchengBlePlugin.PLUGIN_TAG, "address: " + device.deviceMac
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
            if (!completer.isCompleted) return@launch
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

    override fun isDeviceConnected(device: YuchengDevice?, callback: (Result<Boolean>) -> Unit) {
        Log.d(IS_DEVICE_CONNECTED, "Start isDeviceConnected")
        try {
            if (device == null) {
                try {
                    val isCurrentConnected =
                        isConnected()
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
                isConnected() && selectedDevice?.uuid == device.uuid
            return isConnected
        } catch (_: Exception) {
            false
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun connect(
        device: YuchengDevice, connectTimeInSeconds: Long?, callback: (Result<Boolean>) -> Unit
    ) {
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Start connect")
        val macAddress = device.uuid
        if (selectedDevice?.uuid == macAddress) {
            callback(Result.success(true))
            return
        }
        selectedDevice = device
        val bleDevice = scannedDevices.find { it.deviceMac == selectedDevice!!.uuid }
        if (bleDevice == null) {
            callback(Result.success(false))
            return
        }
        val completer = CompletableDeferred<Boolean>()
        val state = YCBTClient.connectState()
        Log.d(YUCHENG_API, "Connect state = $state")
        YCBTClient.connectBleDevice(bleDevice.device) { code ->
            val state = YCBTClient.connectState()
            Log.d(YUCHENG_API, "Connect state = $state")
            if (code == 0) {
                Log.d(YUCHENG_API, "CONNECTED")
                val state = YCBTClient.connectState()
                val isConnected = isConnected()
                Log.d(YUCHENG_API, "connectState() == $state")
                if (!completer.isCompleted) completer.complete(isConnected)
            }
        }
        GlobalScope.launch {
            callback(Result.success(completer.await()))
        }
        GlobalScope.launch {
            val timeout = (connectTimeInSeconds ?: (TIME_TO_TIMEOUT + 10))
            delay(1000 * timeout)
            if (completer.isCompleted) return@launch
            onState(YuchengDeviceStateTimeOutEvent(isTimeout = true))
            completer.complete(false)
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun reconnect(uuid: String?, reconnectTimeInSeconds: Long?, callback: (Result<Boolean>) -> Unit) {
        val bindMac = YCBTClient.getBindDeviceMac()
        if (uuid == bindMac && isConnected()) {
            Log.d(YUCHENG_API, "UUID == BIND MAC and CONNECTED!")
            val macAddress = bindMac
            val deviceName = YCBTClient.getBindDeviceName()
            val ycDevice = YuchengDevice(index++, deviceName, macAddress, true)
            selectedDevice = ycDevice
            onDevice(
                YuchengDeviceDataEvent(
                    ycDevice.index,
                    ycDevice.uuid,
                    ycDevice.isReconnected,
                    ycDevice.deviceName,
                )
            )
            callback(Result.success(true))
            return
        }
        val macAddress = uuid ?: bindMac
        Log.e(YUCHENG_API, "START RECONNECT")
        val completer = CompletableDeferred<Boolean>()
        try {
            YCBTClient.reconnectDevice(macAddress) { code ->
                Log.e("RECONNECT BLE", "CODE = $code")
                Log.e(YUCHENG_API, "RECONNECT, CODE = $code")
                if (code == 0) {
                    val isConnected = isConnected()
                    if (!isConnected) {
                        Log.d(YUCHENG_API, "Test when isConnected = false")
                        YCBTClient.startScanBle( { _, device ->
                            if (device.deviceMac == macAddress) {
                                YCBTClient.connectBleDevice(device.device) { code ->
                                    if (code == 0) {
                                        val isConnected = isConnected()
                                        if (isConnected) {
                                            Log.d(
                                                YUCHENG_API,
                                                "Code = 0, isConnected = false, but CONNECTED!"
                                            )
                                            val macAddress = device.deviceMac
                                            val deviceName = device.deviceName
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
                                            if (!completer.isCompleted) completer.complete(
                                                true
                                            )
                                        } else {
                                            if (!completer.isCompleted) completer.complete(
                                                false
                                            )
                                        }
                                    } else {
                                        Log.d(YUCHENG_API, "Code != 0, isConnected = false, cant connect")
                                    }
                                    YCBTClient.stopScanBle()
                                }
                            }
                        }, SCAN_PERIOD)
                    } else {
                        Log.d(YUCHENG_API, "NORMAL RECONNECT")
                        val macAddress = YCBTClient.getBindDeviceMac()
                        val deviceName = YCBTClient.getBindDeviceName()
                        val ycDevice = YuchengDevice(index++, deviceName, macAddress, true)
                        selectedDevice = ycDevice
                        onDevice(
                            YuchengDeviceDataEvent(
                                ycDevice.index,
                                ycDevice.uuid,
                                ycDevice.isReconnected,
                                ycDevice.deviceName,
                            )
                        )
                        if (!completer.isCompleted) completer.complete(true)
                    }
                } else {
                    Log.d(YUCHENG_API, "Test when cant reconnect (code != 0)")
                    val macAddress = YCBTClient.getBindDeviceMac()
                    YCBTClient.startScanBle( { _, device ->
                        if (device.deviceMac == macAddress) {
                            YCBTClient.connectBleDevice(device.device) { code ->
                                if (code == 0) {
                                    val isConnected = isConnected()
                                    if (isConnected) {
                                        Log.d(
                                            YUCHENG_API,
                                            "Code = 0, isConnected = false, but CONNECTED!"
                                        )
                                        val macAddress = device.deviceMac
                                        val deviceName = device.deviceName
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
                                        if (!completer.isCompleted) completer.complete(
                                            true
                                        )
                                    } else {
                                        if (!completer.isCompleted) completer.complete(
                                            false
                                        )
                                    }
                                    YCBTClient.stopScanBle()
                                } else {
                                    Log.d(YUCHENG_API, "Code != 0, isConnected = false, cant connect")
                                }
                            }
                        }
                    }, SCAN_PERIOD)
                }
            }
        } catch (e: Exception) {
            if (!completer.isCompleted) completer.completeExceptionally(e)
        }
        GlobalScope.launch {
            try {
                callback(Result.success(completer.await()))
                Log.e(YUCHENG_API, "RECONNECT DONE")
                val state = YCBTClient.connectState()
                Log.d(YUCHENG_API, "Connect state = $state")
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
        GlobalScope.launch {
            val timeout = (reconnectTimeInSeconds ?: (TIME_TO_TIMEOUT * 6))
            delay(1000 * timeout)
            if (completer.isCompleted) return@launch
            onState(YuchengDeviceStateTimeOutEvent(isTimeout = true))
            completer.complete(false)
        }
    }

    override fun disconnect(callback: (Result<Unit>) -> Unit) {
        try {
            YCBTClient.disconnectBle()
            selectedDevice = null
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
        if (!isConnected()) {
            Log.d(YuchengBlePlugin.PLUGIN_TAG, "No connection")
            throw NoConnectionException()
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
                if (!sleepDataCompleter.isCompleted) sleepDataCompleter.complete(sleepDataList)
            }
        } catch (e: Exception) {
            Log.e(GET_SLEEP_DATA, e.toString())
            if (!sleepDataCompleter.isCompleted) sleepDataCompleter.completeExceptionally(e)
        }

        GlobalScope.launch {
            delay(1000 * TIME_TO_TIMEOUT)
            if (sleepDataCompleter.isCompleted) return@launch
            if (!skipHandler) {
                for (sleep in sleepDataList) {
                    val ycDataEvent = YuchengSleepDataEvent(sleep)
                    onSleepData(ycDataEvent)
                }
            }
            sleepDataCompleter.complete(sleepDataList)
            onSleepData(YuchengSleepTimeOutEvent(isTimeout = true))
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
                val start: Long = startTimestamp ?: default.start
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
            if (macAddress.isEmpty()) {
                callback(Result.success(null))
                return
            }
            val ycDevice = YuchengDevice(index++, deviceName, macAddress, false)
            selectedDevice = ycDevice
            callback(Result.success(ycDevice))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    private suspend fun getHealthSportData(
        skipHandler: Boolean = false,
        startTimestamp: Long,
        endTimestamp: Long,
    ): YuchengHealthSportData {
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Get health data")
        if (!isConnected()) {
            Log.d(YuchengBlePlugin.PLUGIN_TAG, "No connection")
            throw NoConnectionException()
        }
        val healthDataCompleter = CompletableDeferred<List<YuchengHealthData>>()
        val healthDataList: MutableList<YuchengHealthData> = mutableListOf()
        val sportDataCompleter = CompletableDeferred<List<YuchengSportData>>()
        val sportDataList: MutableList<YuchengSportData> = mutableListOf()
        try {
            YCBTClient.healthHistoryData(Constants.DATATYPE.Health_HistorySport) { code, ratio, data ->
                if (data != null) {
                    val sportData = data["data"] as List<*>? ?: return@healthHistoryData
                    val mappedSport = sportData.map {
                        val yuchengSportData = sportDataConverter.convert(it)
                        return@map yuchengSportData
                    }.filter {
                        val isInRange =
                            it.startTimeStamp >= startTimestamp && it.endTimeStamp <= endTimestamp
                        return@filter isInRange
                    }
                    sportDataList.addAll(mappedSport)
                    Log.d("SPORT DATA CONVERTED", mappedSport.toString())
                } else {
                    Log.e("NO SPORT DATA", "NO SPORT DATA")
                }
                Log.d("SPORT CODE", code.toString())
                Log.d("SPORT RATIO", ratio.toString())
                if (!sportDataCompleter.isCompleted) {
                    sportDataCompleter.complete(sportDataList)
                }
            }
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
            if (!healthDataCompleter.isCompleted) {
                healthDataCompleter.completeExceptionally(e)
            }
        }

        GlobalScope.launch {
            delay(1000 * TIME_TO_TIMEOUT)
            if (healthDataCompleter.isCompleted) return@launch
            if (!skipHandler) {
                val healthSportData = YuchengHealthSportData(healthDataList, sportDataList)
                val ycDataEvent = YuchengHealthDataEvent(healthSportData)
                onHealthData(ycDataEvent)
            }
            healthDataCompleter.complete(healthDataList)
            onHealthData(YuchengHealthTimeOutEvent(isTimeout = true))

        }

        try {
            val healthData = healthDataCompleter.await()
            val sportData = sportDataCompleter.await()
            Log.d("HEALTH DATA", healthData.toString())
            Log.d("SPORT DATA", sportData.toString())
            if (!skipHandler) {
                val healthSportData = YuchengHealthSportData(healthDataList, sportDataList)
                val ycDataEvent = YuchengHealthDataEvent(healthSportData)
                onHealthData(ycDataEvent)
            }
            return YuchengHealthSportData(healthData, sportData)
        } catch (e: Exception) {
            Log.e("GET HEALTH DATA ERROR", e.toString())
            throw e
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    @OptIn(DelicateCoroutinesApi::class)
    override fun getHealthSportData(
        startTimestamp: Long?,
        endTimestamp: Long?, callback: (Result<YuchengHealthSportData>) -> Unit,
    ) {
        GlobalScope.launch {
            try {
                val default = StartEndTimestamp.default()
                val start: Long = startTimestamp ?: default.start
                val end: Long = endTimestamp ?: default.end
                val healthData = getHealthSportData(startTimestamp = start, endTimestamp = end)
                callback(Result.success(healthData))
            } catch (e: Exception) {
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
        if (!isConnected()) {
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
                    getSleepData(skipHandler = true, startTimestamp = start, endTimestamp = end)
                val healthData = getHealthSportData(
                    skipHandler = true, startTimestamp = start, endTimestamp = end
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

        if (!isConnected()) {
            Log.d(YUCHENG_API, "Device not connected")
            completer.completeExceptionally(NoConnectionException())
        }

        GlobalScope.launch {
            try {
                YCBTClient.getDeviceInfo { code, ratio, data ->
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

        if (!isConnected()) {
            Log.d(YUCHENG_API, "Device not connected")
            completer.complete(false)
        }

        try {
            YCBTClient.deleteHealthHistoryData(healthType) { code, ratio, data ->
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

        if (!isConnected()) {
            Log.d(YUCHENG_API, "Device not connected")
            completer.complete(false)
        }

        try {
            YCBTClient.settingRestoreFactory { code, ratio, data ->
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
        val heartCompleter = CompletableDeferred<Boolean>()
        val bloodCompleter = CompletableDeferred<Boolean>()
        try {
            YCBTClient.settingHeartMonitor(0x01, interval.toInt()) { code, ratio, data ->
                if (heartCompleter.isCompleted) return@settingHeartMonitor
                if (code == 0) {
                    heartCompleter.complete(true)
                } else {
                    heartCompleter.complete(false)
                }
            }
            YCBTClient.settingBloodOxygenModeMonitor(true, interval.toInt()) { code, ratio, data ->
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
                callback(Result.success(heartResult && bloodResult))
            } catch (e: Exception) {
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
                                    if (type == REAL_HEART_RATE_TYPE) {
                                        val sum = heartRates.reduce { prev, next -> prev + next }
                                        var count = heartRates.count()
                                        count = if (count < 1) 1 else count
                                        val mean = sum / count
                                        Log.d(YUCHENG_API, "Heart rate mean: $mean")
                                        heartRateCompleter.complete(mean)
                                    } else if (type == REAL_BLOOD_OXYGEN_TYPE) {
                                        val sum = bloodOxygens.reduce { prev, next -> prev + next }
                                        var count = bloodOxygens.count()
                                        count = if (count < 1) 1 else count
                                        val mean = sum / count
                                        Log.d(YUCHENG_API, "Blood oxygen mean: $mean")
                                        bloodOxygenCompleter.complete(mean)
                                    } else if (type == REAL_BLOOD_PRESSURE_TYPE) {
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

                YCBTClient.appStartMeasurement(1, REAL_HEART_RATE_TYPE) { code, ratio, data ->
                    Log.d(YUCHENG_API, "START HEART RATE MEASURE")
                }
                Log.d(YUCHENG_API, "WAITING HEART RATE")
                heartRate = heartRateCompleter.await()
                Log.d(YUCHENG_API, "HEART RATE = $heartRate")
                YCBTClient.appStartMeasurement(1, REAL_BLOOD_PRESSURE_TYPE) { code, ratio, data ->
                    Log.d(YUCHENG_API, "START BLOOD PRESSURE MEASURE")
                }
                Log.d(YUCHENG_API, "WAITING BLOOD PRESSURE")
                bloodPressure = bloodPressureCompleter.await()
                Log.d(YUCHENG_API, "BLOOD PRESSURE = $bloodPressure")

                YCBTClient.appStartMeasurement(1, REAL_BLOOD_OXYGEN_TYPE) { code, ratio, data ->
                    Log.d(YUCHENG_API, "START BLOOD OXYGEN MEASURE")
                }
                Log.d(YUCHENG_API, "WAITING BLOOD OXYGEN")
                bloodOxygen = bloodOxygenCompleter.await()
                Log.d(YUCHENG_API, "BLOOD OXYGEN = $bloodOxygen")
                YCBTClient.appRealDataFromDevice(1, 0) { code, ratio, data ->
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
        if (!isConnected()) {
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
        if (!isConnected()) {
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
        if (!isConnected()) {
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

        YCBTClient.appStartMeasurement(0, type) { code, ratio, data ->
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
        if (!isConnected()) {
            Log.d(YUCHENG_API, "Device not connected")
            callback(Result.failure(NoConnectionException()))
            return
        }
        val completed = CompletableDeferred<Boolean>()
        YCBTClient.appBloodCalibration(sbp.toInt(), dbp.toInt(), { code, ratio, data ->
            if (completed.isCompleted) return@appBloodCalibration
            val isCompleted = code == 0
            if (isCompleted) {
                Log.d(YUCHENG_API, "Calibration is completed")
            } else {
                Log.d(YUCHENG_API, "Calibration is NOT completed")
            }
            completed.complete(isCompleted)
        })

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
            YCBTClient.appStartMeasurement(1, measureDataType) { code, ratio, data ->
                Log.d(YUCHENG_API, "START MEASURE")
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

    private fun isConnected(): Boolean {
        val state = YCBTClient.connectState()
        Log.d(YUCHENG_API, "isConnected(): CONNECT STATE = $state")
        return YCBTClient.connectState() >= 6
    }

    companion object {
        private const val REAL_BLOOD_OXYGEN_TYPE = 2
        private const val REAL_HEART_RATE_TYPE = 0
        private const val REAL_BLOOD_PRESSURE_TYPE = 1
        private const val YUCHENG_API = "YUCH_API"
        private const val GET_SLEEP_DATA = "$YUCHENG_API GET_SLEEP_DATA"
        private const val GET_HEALTH_DATA = "$YUCHENG_API GET_HEALTH_DAT"
        private const val GET_SLEEP_HEALTH_DATA = "GET_SLEEP_HEALTH_DATA"
        private const val DISCONNECT = "$YUCHENG_API DISCONNECT"
        private const val START_SCAN = "$YUCHENG_API START SCAN"
        private const val IS_DEVICE_CONNECTED = "$YUCHENG_API IS_DEV_CON"
        private const val UPDATE_FIRMWARE = "$YUCHENG_API UPDATE_FIRM"
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