package com.crefter.yuchengplugin.yucheng_ble


import YuchengDevice
import YuchengDeviceCompleteEvent
import YuchengDeviceDataEvent
import YuchengDeviceEvent
import YuchengHostApi
import YuchengProductState
import YuchengProductStateDataEvent
import YuchengProductStateEvent
import YuchengSleepEvent
import android.util.Log
import com.yucheng.ycbtsdk.Constants
import com.yucheng.ycbtsdk.YCBTClient
import com.yucheng.ycbtsdk.bean.ScanDeviceBean
import com.yucheng.ycbtsdk.response.BleScanResponse
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import kotlin.Boolean
import kotlin.Double
import kotlin.Exception
import kotlin.Int
import kotlin.Long
import kotlin.Result
import kotlin.Unit


private const val SCAN_PERIOD: Int = 10

class YuchengApiImpl(
    private val onDevice: (device: YuchengDeviceEvent) -> Unit,
    private val onSleepData: (sleepData: YuchengSleepEvent) -> Unit,
    private val onState: (state: YuchengProductStateEvent) -> Unit,
) : YuchengHostApi {

    private var index: Long = 0
    private var devices: MutableList<YuchengDevice> = mutableListOf()
    private var selectedDevice: YuchengDevice? = null
    private val sleepDataList: MutableList<YuchengSleepEvent> = mutableListOf()
    private val sleepDataCompleter = CompletableDeferred<List<YuchengSleepEvent>?>()

    override fun startScanDevices(scanTimeInSeconds: Double?) {
        if (YCBTClient.isScaning()) {
            YCBTClient.stopScanBle();
        }
        try {
            Log.d(YuchengBlePlugin.PLUGIN_TAG, "Start scan")
            YCBTClient.startScanBle(BleScanResponse { _, device ->
                if (device == null) {
                    onDevice(YuchengDeviceCompleteEvent(completed = true))
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
        }
    }

    override fun isDeviceConnected(device: YuchengDevice, callback: (Result<Boolean>) -> Unit) {
        Log.d(IS_DEVICE_CONNECTED, "Start isDeviceConnected")
        try {
            if (isDeviceConnected(device)) {
                callback(Result.success(true))
                Log.d(IS_DEVICE_CONNECTED, "End isDeviceConnected")
            } else {
                callback(Result.success(false))
            }
        } catch (e: Exception) {
            Log.e(IS_DEVICE_CONNECTED, "Exception when is device connected: $e")
            callback(Result.failure(e))
        }
    }

    private fun isDeviceConnected(device: YuchengDevice?): Boolean {
        if (device == null) return false
        if (!devices.contains(device)) return false
        return YCBTClient.connectState() == Constants.BLEState.Connected
    }

    override fun connect(device: YuchengDevice?, callback: (Result<Boolean>) -> Unit) {
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Start connect")
        val macAddress = device?.uuid
        if (macAddress == null) {
            Result.success(false)
            return
        }
        selectedDevice = device
        YCBTClient.connectBle(macAddress) { state ->
            when (state) {
                Constants.BLEState.Connected -> {
                    onState(YuchengProductStateDataEvent(YuchengProductState.CONNECTED))
                }

                Constants.BLEState.TimeOut -> {
                    onState(YuchengProductStateDataEvent(YuchengProductState.TIME_OUT))
                    callback(Result.success(false))
                    return@connectBle
                }

                Constants.BLEState.Disconnect -> {
                    onState(YuchengProductStateDataEvent(YuchengProductState.DISCONNECTED))
                    callback(Result.success(false))
                    return@connectBle
                }

                else -> {
                    onState(YuchengProductStateDataEvent(YuchengProductState.UNKNOWN))
                    callback(Result.success(false))
                    return@connectBle
                }
            }
            callback(Result.success(true))
        }
        try {
            Log.d(YuchengBlePlugin.PLUGIN_TAG, "Try connect")
            YCBTClient.healthHistoryData(
                Constants.DATATYPE.Health_HistorySleep
            ) { code, ratio, data ->
                if (data != null) {
                    Log.d("SLEEP DATA", data.toString())
                } else {
                    Log.e("NO SLEEP DATA", "NO SLEEP DATA")
                }
                Log.d("SLEEP CODE", code.toString())
                Log.d("SLEEP RATIO", ratio.toString())
            }
            callback(Result.success(true))
        } catch (e: Exception) {
            Log.e(CONNECT, e.toString())
            callback(Result.failure(e))
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
        if (!isDeviceConnected(selectedDevice)) callback(Result.success(listOf()))
        if (sleepDataList.isNotEmpty()) callback(Result.success(sleepDataList))

        try {
            YCBTClient.healthHistoryData(
                Constants.DATATYPE.Health_HistorySleep
            ) { code, ratio, data ->
                if (data != null) {
                    Log.d("SLEEP DATA", data.toString())
                } else {
                    Log.e("NO SLEEP DATA", "NO SLEEP DATA")
                }
                Log.d("SLEEP CODE", code.toString())
                Log.d("SLEEP RATIO", ratio.toString())
                sleepDataCompleter.complete(null)
            }
        } catch (e: Exception) {
            Log.e(GET_SLEEP_DATA, e.toString())
            callback(Result.failure(e))
            sleepDataCompleter.completeExceptionally(e)
        }
        GlobalScope.launch {
            try {
                val sleepData = sleepDataCompleter.await()
                callback(Result.success(sleepData ?: listOf()))
                sleepDataList.clear()
            } catch (e: Exception) {
                Log.e("GET SLEEP DATA ERROR", e.toString())
            }
        }
    }

    override fun getCurrentConnectedDevice(callback: (Result<YuchengDevice?>) -> Unit) {
        callback(Result.success(null))
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