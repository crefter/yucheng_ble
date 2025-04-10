package com.crefter.yuchengplugin.yucheng_ble


import YuchengDevice
import YuchengDeviceCompleteEvent
import YuchengDeviceDataEvent
import YuchengDeviceEvent
import YuchengDeviceStateDataEvent
import YuchengDeviceStateEvent
import YuchengHostApi
import YuchengProductState
import YuchengSleepEvent
import android.util.Log
import com.yucheng.ycbtsdk.Constants
import com.yucheng.ycbtsdk.YCBTClient
import com.yucheng.ycbtsdk.response.BleScanResponse
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch


private const val SCAN_PERIOD: Int = 10

class YuchengApiImpl(
    private val onDevice: (device: YuchengDeviceEvent) -> Unit,
    private val onSleepData: (sleepData: YuchengSleepEvent) -> Unit,
    private val onState: (state: YuchengDeviceStateEvent) -> Unit,
    private val sleepDataConverter: YuchengSleepDataConverter,
) : YuchengHostApi {

    init {
        YCBTClient.registerBleStateChange { state ->
            when (state) {
                Constants.BLEState.Connected -> {
                    onState(YuchengDeviceStateDataEvent(YuchengProductState.CONNECTED))
                }

                Constants.BLEState.TimeOut -> {
                    onState(YuchengDeviceStateDataEvent(YuchengProductState.TIME_OUT))
                }

                Constants.BLEState.Disconnect -> {
                    onState(YuchengDeviceStateDataEvent(YuchengProductState.DISCONNECTED))
                }

                Constants.BLEState.ReadWriteOK -> {
                    onState(YuchengDeviceStateDataEvent(YuchengProductState.READ_WRITE_OK))
                }

                else -> {
                    onState(YuchengDeviceStateDataEvent(YuchengProductState.UNKNOWN))
                }
            }
        }
    }

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
            delay(1000 * 15)
            if (!completer.isCompleted) completer.complete(devices)
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
            delay(1000 * 15)
            if (!completer.isCompleted) completer.complete(false)
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun reconnect(callback: (Result<Boolean>) -> Unit) {
        val completer = CompletableDeferred<Boolean>()
        try {
            YCBTClient.reconnectBle {
                val isConnected = YCBTClient.connectState() == Constants.BLEState.ReadWriteOK;
                completer.complete(isConnected)
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
            delay(1000 * 15)
            if (!completer.isCompleted) completer.complete(false)
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
    override fun getSleepData(callback: (Result<List<YuchengSleepEvent?>>) -> Unit) {
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Get sleep data")
        if (YCBTClient.connectState() != Constants.BLEState.ReadWriteOK) {
            callback(Result.success(listOf()))
        }
        val sleepDataCompleter = CompletableDeferred<List<YuchengSleepEvent>>()
        val sleepDataList: MutableList<YuchengSleepEvent> = mutableListOf()
        try {
            YCBTClient.healthHistoryData(
                Constants.DATATYPE.Health_HistorySleep
            ) { code, ratio, data ->
                if (data != null) {
                    val sleepData = data["data"] as List<*>? ?: return@healthHistoryData
                    val sleepEvents = sleepData.map {
                        val yuchengSleepEvent = sleepDataConverter.convert(it)
                        return@map yuchengSleepEvent
                    }
                    sleepDataList.addAll(sleepEvents)
                    for (i in 0 until sleepDataList.size) {
                        onSleepData(sleepEvents[i])
                    }
                    Log.d("SLEEP DATA CONVERTED", sleepEvents.toString())
                } else {
                    Log.e("NO SLEEP DATA", "NO SLEEP DATA")
                }
                Log.d("SLEEP CODE", code.toString())
                Log.d("SLEEP RATIO", ratio.toString())
                if (sleepDataCompleter.isCompleted == false) {
                    sleepDataCompleter.complete(sleepDataList)
                }
            }
        } catch (e: Exception) {
            Log.e(GET_SLEEP_DATA, e.toString())
            callback(Result.failure(e))
            sleepDataCompleter.completeExceptionally(e)
        }
        GlobalScope.launch {
            try {
                val sleepData = sleepDataCompleter.await()
                callback(Result.success(sleepData))
            } catch (e: Exception) {
                Log.e("GET SLEEP DATA ERROR", e.toString())
                callback(Result.failure(e))
            }
        }

        GlobalScope.launch {
            delay(1000 * 10)
            if (sleepDataCompleter.isCompleted == false) {
                sleepDataCompleter.complete(sleepDataList)
            }
        }
    }

    override fun getCurrentConnectedDevice(callback: (Result<YuchengDevice?>) -> Unit) {
        try {
            callback(Result.success(selectedDevice))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }


    companion object {
        private const val YUCHENG_API = "YUCH_API"
        private const val GET_SLEEP_DATA = "$YUCHENG_API GET_SLEEP_DATA"
        private const val CONNECT = "$YUCHENG_API CONNECT"
        private const val DISCONNECT = "$YUCHENG_API DISCONNECT"
        private const val START_SCAN = "$YUCHENG_API START SCAN"
        private const val IS_DEVICE_CONNECTED = "$YUCHENG_API IS_DEV_CON"
    }
}