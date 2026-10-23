@file:OptIn(ExperimentalAtomicApi::class)

package com.crefter.yuchengplugin.yucheng_ble

import android.content.Context
import android.os.Build
import android.util.Log
import com.crefter.yuchengplugin.yucheng_ble.data.local.DataStorage
import com.crefter.yuchengplugin.yucheng_ble.data.local.YuchengBleStorage
import com.crefter.yuchengplugin.yucheng_ble.data.local.YuchengTokenStorage
import com.crefter.yuchengplugin.yucheng_ble.data.local.yuchengBleStore
import com.crefter.yuchengplugin.yucheng_ble.data.local.yuchengEncryptedDataStore
import com.crefter.yuchengplugin.yucheng_ble.data.remote.startDate
import com.yucheng.ycbtsdk.Constants
import com.yucheng.ycbtsdk.YCBTClient
import com.yucheng.ycbtsdk.bean.ScanDeviceBean
import kotlinx.coroutines.CancellationException
import java.util.concurrent.TimeoutException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.ConcurrentHashMap
import kotlin.concurrent.atomics.AtomicLong
import kotlin.concurrent.atomics.ExperimentalAtomicApi

object YuchengCore {
    private const val YUCHENG_API = "YUCH_API Core"
    private const val GET_SLEEP_DATA = "$YUCHENG_API GET_SLEEP_DATA"
    private const val GET_HEALTH_DATA = "$YUCHENG_API GET_HEALTH_DAT"
    private const val TIME_TO_TIMEOUT: Long = 15
    private const val SCAN_PERIOD: Int = 20
    private var scannedDevices = ConcurrentHashMap.newKeySet<ScanDeviceBean>()
    private var canLaunchJob: Job? = null
    private var isInit = false
    private val lock = Any()
    private val canLaunchScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    val isTokenRefreshing = MutableStateFlow(false)
    var deviceIndex: AtomicLong = AtomicLong(0)
    var selectedDevice: YuchengDevice? = null
    var storage: YuchengBleStorage? = null
    var serviceOn: Boolean = false
    var connectState = MutableStateFlow(3)
    private val reconnectLock = Any()
    private var reconnectGeneration = 0L
    private var reconnectScanGeneration: Long? = null
    var tokenStorage: YuchengTokenStorage? = null
    fun init(context: Context) {
        if (isInit) {
            Log.e(YUCHENG_API, "YCBTClient init yet!!!")
            return
        }
        synchronized(lock) {
            if (isInit) return
            YCBTClient.initClient(context, true)
            YCBTClient.setReconnect(true)
            isInit = true
            Log.e(YUCHENG_API, "YCBTClient Init!")
        }
        storage = YuchengBleStorage(DataStorage(context.yuchengBleStore))
        tokenStorage = YuchengTokenStorage(yuchengEncryptedDataStore(context.applicationContext))
        if (canLaunchJob != null) {
            canLaunchJob?.cancel()
            canLaunchJob = null
        }
        canLaunchJob = canLaunchScope.launch {
            serviceOn = storage?.readServiceOn() ?: false
            storage?.onServiceOn()?.collect {
                Log.e(YUCHENG_API, "onServiceOn: $it")
                if (it != null) {
                    serviceOn = it
                }
            }
        }
        YCBTClient.registerBleStateChange {
            connectState.value = it
        }
    }

    fun addListenerState(listener: (state: Int) -> Unit) {
        YCBTClient.registerBleStateChange(listener)
    }

    fun removeListenerState(listener: (state: Int) -> Unit) {
        YCBTClient.unRegisterBleStateChange(listener)
    }

    fun dispose() {
        YCBTClient.stopScanBle()
    }

    suspend fun scanDevices(
        scanTimeInSeconds: Long?,
        onDevice: (device: YuchengDeviceEvent) -> Unit = {}
    ): Set<YuchengDevice> {
        Log.d(YUCHENG_API, "Start scan")
        val ycDevices = mutableSetOf<YuchengDevice>()
        val devices = mutableSetOf<ScanDeviceBean>()
        val completer = CompletableDeferred<Set<ScanDeviceBean>>()
        withContext(Dispatchers.Main) {
            synchronized(reconnectLock) {
                // A user scan takes ownership from background reconnect scans.
                ++reconnectGeneration
                reconnectScanGeneration = null
                YCBTClient.startScanBle({ _, device ->
                    if (device == null) {
                        onDevice(YuchengDeviceCompleteEvent(completed = true))
                        if (!completer.isCompleted) completer.complete(devices)
                        Log.d(YUCHENG_API, "End scan")
                    } else {
                        val deviceName = device.deviceName
                        val deviceMac = device.deviceMac
                        if (deviceMac == null || deviceName == null) {
                            return@startScanBle
                        }
                        devices.add(device)
                        Log.d(YUCHENG_API, "name: " + device.deviceName)
                        Log.d(
                            YUCHENG_API, "address: " + device.deviceMac
                        )
                        val ycDevice =
                            YuchengDevice(deviceIndex.fetchAndAdd(1), deviceName, deviceMac, false)
                        ycDevices.add(ycDevice)
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
            }
        }

        val result = withTimeoutOrNull((scanTimeInSeconds ?: SCAN_PERIOD.toLong()) * 1000) {
            completer.await()
        }

        if (result == null) {
            onDevice(
                YuchengDeviceTimeOutEvent(true)
            )
        }
        scannedDevices.addAll(result ?: devices)

        return ycDevices.toSet()
    }

    suspend fun connect(device: YuchengDevice, connectTimeInSeconds: Long): Boolean {
        Log.d(YUCHENG_API, "Start connect")
        val macAddress = device.uuid
        if (selectedDevice?.uuid == macAddress && isConnected()) {
            return true
        }
        selectedDevice = device
        val bleDevice = scannedDevices.find { it.deviceMac == selectedDevice!!.uuid }
        if (bleDevice == null) {
            return false
        }
        val completer = CompletableDeferred<Boolean>()
        val state = YCBTClient.connectState()
        Log.d(YUCHENG_API, "Connect state = $state")
        withContext(Dispatchers.Main) {
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
        }

        val result = withTimeout(connectTimeInSeconds * 1000) {
            completer.await()
        }

        return result
    }

    suspend fun reconnect(
        uuid: String?,
        reconnectTimeInSeconds: Long,
        scanPeriod: Int = 20,
        onDevice: (device: YuchengDeviceEvent) -> Unit = {}
    ): Boolean = withTimeout(reconnectTimeInSeconds * 1000) {
        val generation = synchronized(reconnectLock) { ++reconnectGeneration }
        var active = true
        fun stopScanIfOwned() {
            synchronized(reconnectLock) {
                if (reconnectScanGeneration == generation) {
                    reconnectScanGeneration = null
                    YCBTClient.stopScanBle()
                }
            }
        }
        val bindMac = YCBTClient.getBindDeviceMac()
        delay(1000)
        Log.e(
            YUCHENG_API,
            "START RECONNECT, bindMac: $bindMac, deviceMac: $uuid, isConnected = ${isConnected()}"
        )
        if (connectState.value == 5) {
            Log.d(YUCHENG_API, "RECONNECT: device connecting, wait until state >= 6 (Connected)")
            connectState.first { it >= Constants.BLEState.Connected }
        }
        synchronized(reconnectLock) {
            if (generation != reconnectGeneration) return@withTimeout false
            val currentMac = YCBTClient.getBindDeviceMac()
            if (currentMac != null && uuid.equals(currentMac, ignoreCase = true) && isConnected()) {
                Log.d(YUCHENG_API, "UUID == BIND MAC and CONNECTED!")
                val deviceName = YCBTClient.getBindDeviceName()
                val ycDevice = YuchengDevice(deviceIndex.fetchAndAdd(1), deviceName, currentMac, true)
                selectedDevice = ycDevice
                onDevice(
                    YuchengDeviceDataEvent(
                        ycDevice.index,
                        ycDevice.uuid,
                        ycDevice.isReconnected,
                        ycDevice.deviceName,
                    )
                )
                return@withTimeout true
            }
        }
        val macAddress = (uuid ?: YCBTClient.getBindDeviceMac())?.uppercase()
        Log.e(YUCHENG_API, "RECONNECT, BIND MAC != DEVICE MAC, bindMac: $bindMac, deviceMac: $uuid")
        val completer = CompletableDeferred<Boolean>()
        if (macAddress == null) {
            return@withTimeout false
        }
        fun hasExpectedDevice(): Boolean =
            YCBTClient.getBindDeviceMac()?.equals(macAddress, ignoreCase = true) == true
        coroutineScope {
            val jobAutoReconnect = launch(Dispatchers.Main) {
                Log.e(YUCHENG_API, "reconnect: start auto reconnect (listen state)")
                connectState.first {
                    it == Constants.BLEState.ReadWriteOK && hasExpectedDevice()
                }
                synchronized(reconnectLock) {
                    if (!active || generation != reconnectGeneration || completer.isCompleted ||
                        !hasExpectedDevice()) return@launch
                    val ycDevice = YuchengDevice(
                        deviceIndex.fetchAndAdd(1), YCBTClient.getBindDeviceName(), macAddress, true
                    )
                    selectedDevice = ycDevice
                    onDevice(YuchengDeviceDataEvent(
                        ycDevice.index, ycDevice.uuid, ycDevice.isReconnected, ycDevice.deviceName
                    ))
                    Log.e(YUCHENG_API, "reconnect: auto reconnect: complete!!!")
                    completer.complete(true)
                }
            }
            val jobReconnect = launch(Dispatchers.Main) {
                Log.e(YUCHENG_API, "reconnect: start manual reconnect")
                try {
                    synchronized(reconnectLock) {
                        if (!active || generation != reconnectGeneration || completer.isCompleted) return@launch
                        YCBTClient.reconnectDevice(macAddress) { code ->
                            synchronized(reconnectLock) {
                                if (!active || generation != reconnectGeneration || completer.isCompleted) return@reconnectDevice
                                Log.e("RECONNECT BLE", "CODE = $code")
                                Log.e(YUCHENG_API, "RECONNECT, CODE = $code")
                                if (code == 0) {
                                    val isConnected = isConnected()
                                    if (!isConnected) {
                                        Log.d(YUCHENG_API, "Test when isConnected = false")
                                        reconnectScanGeneration = generation
                                        YCBTClient.startScanBle({ _, device ->
                                            synchronized(reconnectLock) {
                                                if (!active || generation != reconnectGeneration || completer.isCompleted) return@startScanBle
                                                Log.d(YUCHENG_API, "RECONNECT, DEVICE SCAN: $device")
                                                val deviceMac = device.deviceMac
                                                if (deviceMac == null) {
                                                    Log.d(YUCHENG_API, "code == 0, deviceMac is null")
                                                    return@startScanBle
                                                }
                                                if (deviceMac.equals(macAddress, ignoreCase = true)) {
                                                    Log.d(
                                                        YUCHENG_API,
                                                        "DEVICE FOUND! Device: ${device.deviceName}:${device.deviceMac}, Mac: $macAddress"
                                                    )
                                                    val deviceDevice = device.device
                                                    if (deviceDevice == null) {
                                                        Log.d(YUCHENG_API, "code == 0, device.device is null")
                                                        return@startScanBle
                                                    }
                                                    YCBTClient.connectBleDevice(deviceDevice) { code ->
                                                        synchronized(reconnectLock) {
                                                            if (!active || generation != reconnectGeneration || completer.isCompleted) return@connectBleDevice
                                                            Log.d(YUCHENG_API, "Try connect, code = $code")
                                                            if (code == 0) {
                                                                val isConnected = isConnected()
                                                                if (isConnected) {
                                                                    if (!hasExpectedDevice()) {
                                                                        completer.complete(false)
                                                                        return@connectBleDevice
                                                                    }
                                                                    Log.d(
                                                                        YUCHENG_API,
                                                                        "Code = 0, isConnected = true, but CONNECTED!"
                                                                    )
                                                                    val deviceName = device.deviceName
                                                                    if (deviceName == null) {
                                                                        Log.d(
                                                                            YUCHENG_API,
                                                                            "macAddress = $macAddress, deviceName = $deviceName, NULL!"
                                                                        )
                                                                        if (!completer.isCompleted) {
                                                                            completer.complete(false)
                                                                            return@connectBleDevice
                                                                        }
                                                                    }
                                                                    val ycDevice =
                                                                        YuchengDevice(
                                                                            deviceIndex.fetchAndAdd(1),
                                                                            deviceName,
                                                                            macAddress,
                                                                            true
                                                                        )
                                                                    selectedDevice = ycDevice
                                                                    onDevice(
                                                                        YuchengDeviceDataEvent(
                                                                            ycDevice.index,
                                                                            ycDevice.uuid,
                                                                            ycDevice.isReconnected,
                                                                            ycDevice.deviceName,
                                                                        )
                                                                    )
                                                                    if (!completer.isCompleted) {
                                                                        Log.d(
                                                                            YUCHENG_API,
                                                                            "Completer is NOT completed, value = true"
                                                                        )
                                                                        completer.complete(
                                                                            true
                                                                        )
                                                                    } else {
                                                                        Log.d(YUCHENG_API, "Completed is completed")
                                                                    }
                                                                    stopScanIfOwned()
                                                                } else {
                                                                    if (!completer.isCompleted) {
                                                                        Log.d(
                                                                            YUCHENG_API,
                                                                            "Completer is NOT completed, value = false"
                                                                        )
                                                                        completer.complete(
                                                                            false
                                                                        )
                                                                    } else {
                                                                        Log.d(YUCHENG_API, "Completed is completed")
                                                                    }
                                                                }
                                                            } else {
                                                                Log.d(
                                                                    YUCHENG_API,
                                                                    "Code != 0, isConnected = false, cant connect"
                                                                )
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }, scanPeriod)
                                    } else {
                                        Log.d(YUCHENG_API, "NORMAL RECONNECT")
                                        if (!hasExpectedDevice()) {
                                            completer.complete(false)
                                            return@reconnectDevice
                                        }
                                        val deviceName = YCBTClient.getBindDeviceName()
                                        if (deviceName == null) {
                                            Log.d(
                                                YUCHENG_API,
                                                "macAddress = $macAddress, deviceName = $deviceName, NULL!"
                                            )
                                            if (!completer.isCompleted) {
                                                completer.complete(false)
                                            }
                                            return@reconnectDevice
                                        }
                                        val ycDevice =
                                            YuchengDevice(
                                                deviceIndex.fetchAndAdd(1),
                                                deviceName,
                                                macAddress,
                                                true
                                            )
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
                                    reconnectScanGeneration = generation
                                    YCBTClient.startScanBle(
                                        { _, device ->
                                            synchronized(reconnectLock) {
                                                if (!active || generation != reconnectGeneration || completer.isCompleted) return@startScanBle
                                                Log.d(YUCHENG_API, "RECONNECT, DEVICE SCAN: $device")
                                                if (device == null) {
                                                    return@startScanBle
                                                }
                                                val deviceMac = device.deviceMac
                                                if (deviceMac == null) {
                                                    Log.d(YUCHENG_API, "code != 0, deviceMac is null")
                                                    return@startScanBle
                                                }
                                                if (deviceMac.equals(macAddress, ignoreCase = true)) {
                                                    Log.d(
                                                        YUCHENG_API,
                                                        "DEVICE FOUND! Device: ${device.deviceName}:$deviceMac, Mac: $macAddress"
                                                    )
                                                    val deviceDevice = device.device
                                                    if (deviceDevice == null) {
                                                        Log.d(YUCHENG_API, "code != 0, device.device is null")
                                                        return@startScanBle
                                                    }
                                                    YCBTClient.connectBleDevice(deviceDevice) { code ->
                                                        synchronized(reconnectLock) {
                                                            if (!active || generation != reconnectGeneration || completer.isCompleted) return@connectBleDevice
                                                            Log.d(YUCHENG_API, "Try connect, code = $code")
                                                            if (code == 0) {
                                                                Log.d(YUCHENG_API, "Code = 0, device connected!")
                                                                val isConnected = isConnected()
                                                                if (isConnected) {
                                                                    if (!hasExpectedDevice()) {
                                                                        completer.complete(false)
                                                                        return@connectBleDevice
                                                                    }
                                                                    Log.d(
                                                                        YUCHENG_API,
                                                                        "Code = 0, isConnected = true, but CONNECTED!"
                                                                    )
                                                                    val deviceName = device.deviceName
                                                                    if (deviceName == null) {
                                                                        Log.d(
                                                                            YUCHENG_API,
                                                                            "macAddress = $deviceMac, deviceName = $deviceName, NULL!"
                                                                        )
                                                                        if (!completer.isCompleted) {
                                                                            completer.complete(false)
                                                                            return@connectBleDevice
                                                                        }
                                                                    }
                                                                    val ycDevice =
                                                                        YuchengDevice(
                                                                            deviceIndex.fetchAndAdd(1),
                                                                            deviceName,
                                                                            deviceMac,
                                                                            true
                                                                        )
                                                                    selectedDevice = ycDevice
                                                                    onDevice(
                                                                        YuchengDeviceDataEvent(
                                                                            ycDevice.index,
                                                                            ycDevice.uuid,
                                                                            ycDevice.isReconnected,
                                                                            ycDevice.deviceName,
                                                                        )
                                                                    )
                                                                    if (!completer.isCompleted) {
                                                                        Log.d(
                                                                            YUCHENG_API,
                                                                            "Completer is NOT completed, value = true"
                                                                        )
                                                                        completer.complete(
                                                                            true
                                                                        )
                                                                    } else {
                                                                        Log.d(YUCHENG_API, "Completer is completed")
                                                                    }
                                                                    stopScanIfOwned()
                                                                } else {
                                                                    if (!completer.isCompleted) {
                                                                        Log.d(
                                                                            YUCHENG_API,
                                                                            "Completer is NOT completed, value = false"
                                                                        )
                                                                        completer.complete(
                                                                            false
                                                                        )
                                                                    } else {
                                                                        Log.d(YUCHENG_API, "Completer is completed")
                                                                    }
                                                                }
                                                            } else {
                                                                Log.d(
                                                                    YUCHENG_API,
                                                                    "Code != 0, isConnected = false, cant connect"
                                                                )
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        },
                                        scanPeriod,
                                    )
                                }
                            }
                        }
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    if (!completer.isCompleted) completer.completeExceptionally(e)
                }
            }
            try {
                completer.await()
            } finally {
                // Close the attempt on success as well as timeout/cancellation.
                val stopOwnedScan = synchronized(reconnectLock) {
                    active = false
                    completer.cancel()
                    reconnectScanGeneration == generation
                }
                jobReconnect.cancel()
                jobAutoReconnect.cancel()
                if (stopOwnedScan) {
                    withContext(NonCancellable + Dispatchers.Main) {
                        stopScanIfOwned()
                    }
                }
            }
        }
    }

    fun disconnect() {
        Log.d(YUCHENG_API, "Start disconnect")
        try {
            YCBTClient.disconnectBle()
            selectedDevice = null
            Log.d(YUCHENG_API, "Disconnect successful!")
        } catch (e: Exception) {
            Log.e(YUCHENG_API, e.toString())
            throw e
        }
    }

    private suspend fun <T> readHistory(
        type: Int,
        convert: (Any?) -> T,
    ): List<T> {
        val result = CompletableDeferred<List<T>>()
        val callbackLock = Any()
        try {
            YCBTClient.healthHistoryData(type) { code, _, data ->
                synchronized(callbackLock) {
                    if (result.isCompleted) return@healthHistoryData
                    try {
                        check(code == 0) { "History query failed: $code" }
                        // SDK 4.0.9 also returns (0, 0, null) after CRC failure.
                        // Only an actual empty data list proves successful emptiness.
                        val rows = data?.get("data") as? List<*>
                            ?: throw IllegalStateException("History query returned no valid payload")
                        result.complete(rows.map(convert))
                    } catch (e: Exception) {
                        result.completeExceptionally(e)
                    }
                }
            }
            return withTimeoutOrNull(1000 * TIME_TO_TIMEOUT) { result.await() }
                ?: throw TimeoutException("History query timed out")
        } finally {
            // A late or duplicate SDK callback must not mutate a returned list
            // or emit data after timeout/cancellation.
            synchronized(callbackLock) { result.cancel() }
        }
    }

    suspend fun getSleepData(
        skipHandler: Boolean = false,
        startTimestamp: Long,
        endTimestamp: Long,
        sleepDataConverter: YuchengSleepDataConverter,
        onSleepData: (sleepData: YuchengSleepEvent) -> Unit = {}
    ): List<YuchengSleepData> {
        val safety = HistoryReadSafety.sleep
        check(safety.begin()) { "History clear is in progress" }
        var complete = false
        try {
            if (!isConnected()) throw NoConnectionException()
            require(startTimestamp < endTimestamp) { "Start timestamp must precede end timestamp" }
            val all = readHistory(Constants.DATATYPE.Health_HistorySleep, sleepDataConverter::convert)
            val data = all.filter { it.startTimeStamp >= startTimestamp && it.endTimeStamp <= endTimestamp }
            complete = data.size == all.size
            if (!skipHandler) data.forEach { onSleepData(YuchengSleepDataEvent(it)) }
            return data
        } catch (e: TimeoutException) {
            if (!skipHandler) onSleepData(YuchengSleepTimeOutEvent(isTimeout = true))
            throw e
        } finally {
            safety.finish(complete)
        }
    }

    suspend fun getHealthSportData(
        skipHandler: Boolean = false,
        startTimestamp: Long,
        endTimestamp: Long,
        sportDataConverter: YuchengSportDataConverter,
        healthDataConverter: YuchengHealthDataConverter,
        onHealthData: (healthData: YuchengHealthEvent) -> Unit = {},
    ): YuchengHealthSportData = withContext(Dispatchers.IO) {
        val safety = HistoryReadSafety.health
        check(safety.begin()) { "History clear is in progress" }
        var complete = false
        try {
            if (!isConnected()) throw NoConnectionException()
            require(startTimestamp < endTimestamp) { "Start timestamp must precede end timestamp" }
            val errors = mutableListOf<Exception>()
            var filtered = false
            // Preserve the SDK's sequential command ordering; a failed category
            // must not prevent trying the next one. Cancellation still stops it.
            val sport = try {
                val all = readHistory(Constants.DATATYPE.Health_HistorySport, sportDataConverter::convert)
                all.filter { it.startTimeStamp >= startTimestamp && it.endTimeStamp <= endTimestamp }
                    .also { filtered = filtered || it.size != all.size }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                errors.add(e)
                emptyList()
            }
            val health = try {
                val all = readHistory(Constants.DATATYPE.Health_HistoryAll, healthDataConverter::convert)
                all.filter { it.startTimestamp in startTimestamp..endTimestamp }
                    .also { filtered = filtered || it.size != all.size }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                errors.add(e)
                emptyList()
            }
            complete = errors.isEmpty() && !filtered
            if (!skipHandler && errors.any { it is TimeoutException }) {
                onHealthData(YuchengHealthTimeOutEvent(isTimeout = true))
            }
            if (errors.isNotEmpty() && sport.isEmpty() && health.isEmpty()) throw errors.first()
            val data = YuchengHealthSportData(health, sport)
            if (!skipHandler) onHealthData(YuchengHealthDataEvent(data))
            data
        } finally {
            safety.finish(complete)
        }
    }

    fun isConnected(): Boolean {
        val state = YCBTClient.connectState()
        Log.d(YUCHENG_API, "isConnected(): CONNECT STATE = $state")
        return YCBTClient.connectState() >= 6
    }
}