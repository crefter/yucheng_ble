package com.crefter.yuchengplugin.yucheng_ble

import DeviceStateStreamHandler
import DevicesStreamHandler
import SleepDataStreamHandler
import YuchengHostApi
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.gson.Gson
import com.google.gson.GsonBuilder
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
        handler = Handler(Looper.getMainLooper())
        if (handler == null) {
            Log.e(PLUGIN_TAG, "HANDLER IS NULL")
        }
        devicesHandler = DevicesStreamHandlerImpl(handler!!)
        sleepDataHandler = SleepDataHandlerImpl(handler!!)
        deviceStateStreamHandler = DeviceStateStreamHandlerImpl(handler!!)

        gson = GsonBuilder().create()

        YCBTClient.initClient(flutterPluginBinding.applicationContext, true)
        Reconnect.getInstance().init(flutterPluginBinding.applicationContext, true);

        DevicesStreamHandler.register(flutterPluginBinding.binaryMessenger, devicesHandler!!)
        SleepDataStreamHandler.register(flutterPluginBinding.binaryMessenger, sleepDataHandler!!)
        DeviceStateStreamHandler.register(
            flutterPluginBinding.binaryMessenger,
            deviceStateStreamHandler!!
        )

        api = YuchengApiImpl(
            onDevice = { device -> devicesHandler?.onDevice(device) },
            onSleepData = { data -> sleepDataHandler?.onSleepData(data) },
            onState = { data ->  deviceStateStreamHandler?.onState(data) },
            sleepDataConverter = YuchengSleepDataConverter(gson!!),
        )
        YuchengHostApi.setUp(flutterPluginBinding.binaryMessenger, api)
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