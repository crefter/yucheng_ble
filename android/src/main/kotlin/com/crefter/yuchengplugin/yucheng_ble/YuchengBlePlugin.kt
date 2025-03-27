package com.crefter.yuchengplugin.yucheng_ble

import DeviceStateStreamHandler
import YuchengHostApi
import android.os.Build
import androidx.annotation.NonNull
import com.yucheng.ycbtsdk.YCBTClient

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** YuchengBlePlugin */
class YuchengBlePlugin : FlutterPlugin {
    private var api: YuchengApiImpl? = null
    private var devicesHandler: DevicesStreamHandlerImpl? = null
    private var sleepDataHandler: SleepDataHandlerImpl? = null
    private var deviceStateStreamHandler: DeviceStateStreamHandlerImpl? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        devicesHandler = DevicesStreamHandlerImpl()
        sleepDataHandler = SleepDataHandlerImpl()
        deviceStateStreamHandler = DeviceStateStreamHandlerImpl()

        YCBTClient.initClient(flutterPluginBinding.applicationContext, true)

        DevicesStreamHandler.register(flutterPluginBinding.binaryMessenger, devicesHandler!!)
        SleepDataStreamHandler.register(flutterPluginBinding.binaryMessenger, sleepDataHandler!!)
        DeviceStateStreamHandler.register(
            flutterPluginBinding.binaryMessenger,
            deviceStateStreamHandler!!
        )

        api = YuchengApiImpl(
            onDevice = { device -> devicesHandler?.onDevice(device) },
            onSleepData = { data -> sleepDataHandler?.onSleepData(data) },
            onState = { data -> deviceStateStreamHandler?.onState(data) },
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
