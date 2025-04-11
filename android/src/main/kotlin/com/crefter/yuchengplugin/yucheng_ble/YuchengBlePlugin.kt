package com.crefter.yuchengplugin.yucheng_ble

import DeviceStateStreamHandler
import DevicesStreamHandler
import SleepDataStreamHandler
import YuchengDeviceStateDataEvent
import YuchengHostApi
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import com.yucheng.ycbtsdk.Constants
import com.yucheng.ycbtsdk.YCBTClient
import com.yucheng.ycbtsdk.gatt.Reconnect
import io.flutter.embedding.engine.plugins.FlutterPlugin


/** YuchengBlePlugin */
class YuchengBlePlugin : FlutterPlugin {
    private var api: YuchengApiImpl? = null
    private var devicesHandler: DevicesStreamHandlerImpl? = null
    private var sleepDataHandler: SleepDataHandlerImpl? = null
    private var deviceStateStreamHandler: DeviceStateStreamHandlerImpl? = null
    private var gson: Gson? = null
    private var handler: Handler? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Start attaching to engine")
        handler = Handler(Looper.getMainLooper())

        devicesHandler = DevicesStreamHandlerImpl(handler!!)
        sleepDataHandler = SleepDataHandlerImpl(handler!!)
        deviceStateStreamHandler = DeviceStateStreamHandlerImpl(handler!!)

        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Device state stream handler = $deviceStateStreamHandler")

        gson = GsonBuilder().create()

        DevicesStreamHandler.register(flutterPluginBinding.binaryMessenger, devicesHandler!!)
        SleepDataStreamHandler.register(flutterPluginBinding.binaryMessenger, sleepDataHandler!!)
        DeviceStateStreamHandler.register(
            flutterPluginBinding.binaryMessenger,
            deviceStateStreamHandler!!
        )

        api = YuchengApiImpl(
            onDevice = { device -> devicesHandler?.onDevice(device) },
            onSleepData = { data -> sleepDataHandler?.onSleepData(data) },
            sleepDataConverter = YuchengSleepDataConverter(gson!!),
            onReconnect = { Reconnect.getInstance().init(flutterPluginBinding.applicationContext, true)}
        )

        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Device state stream handler = $deviceStateStreamHandler")

        YuchengHostApi.setUp(flutterPluginBinding.binaryMessenger, api)

        YCBTClient.initClient(flutterPluginBinding.applicationContext, false)
        YCBTClient.registerBleStateChange { state ->
            Log.d(YuchengBlePlugin.PLUGIN_TAG, "Device state stream handler register ble state change = $deviceStateStreamHandler")
            when (state) {
                Constants.BLEState.Connected -> {
                    deviceStateStreamHandler?.onState(YuchengDeviceStateDataEvent(YuchengProductState.CONNECTED))
                }
                Constants.BLEState.TimeOut -> {
                    deviceStateStreamHandler?.onState(YuchengDeviceStateDataEvent(YuchengProductState.TIME_OUT))
                }
                Constants.BLEState.Disconnect -> {
                    deviceStateStreamHandler?.onState(YuchengDeviceStateDataEvent(YuchengProductState.DISCONNECTED))
                }
                Constants.BLEState.ReadWriteOK -> {
                    deviceStateStreamHandler?.onState(YuchengDeviceStateDataEvent(YuchengProductState.READ_WRITE_OK))
                }
                else -> {
                    deviceStateStreamHandler?.onState(YuchengDeviceStateDataEvent(YuchengProductState.UNKNOWN))
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        YuchengHostApi.setUp(binding.binaryMessenger, null)
        YCBTClient.stopScanBle()
        devicesHandler?.detach()
        sleepDataHandler?.detach()
        deviceStateStreamHandler?.detach()
    }

    companion object {
        val PLUGIN_TAG: String = "YuchengBlePlugin"
    }
}