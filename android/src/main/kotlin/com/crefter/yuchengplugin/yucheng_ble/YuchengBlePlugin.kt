package com.crefter.yuchengplugin.yucheng_ble

import DeviceStateStreamHandler
import DevicesStreamHandler
import SleepDataStreamHandler
import YuchengDeviceStateDataEvent
import YuchengHostApi
import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.crefter.yuchengplugin.yucheng_ble.PathUtils.getExternalAppCachePath
import com.crefter.yuchengplugin.yucheng_ble.ResourceUtils.copyFileFromAssets
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import com.yucheng.ycbtsdk.Constants
import com.yucheng.ycbtsdk.YCBTClient
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import java.util.UUID


/** YuchengBlePlugin */
class YuchengBlePlugin : FlutterPlugin, ActivityAware {
    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(PLUGIN_TAG, "Start attaching to engine")
        if (handler == null) {
            handler = Handler(Looper.getMainLooper())
        }
        // Инстанс плагина пересоздается, поэтому делаем хендлеры и апи статичными
        // и также присваем однажды, иначе ивенты не прилетят в дарт
        if (devicesHandler == null) {
            devicesHandler = DevicesStreamHandlerImpl(handler!!)
        }
        if (sleepDataHandler == null) {
            sleepDataHandler = SleepDataHandlerImpl(handler!!)
        }
        if (deviceStateStreamHandler == null) {
            deviceStateStreamHandler = DeviceStateStreamHandlerImpl(handler!!)
        }
        if (allStreamHandler == null) {
            allStreamHandler = AllDataStreamHandlerImpl(handler!!)
        }
        if (healthStreamHandler == null) {
            healthStreamHandler = HealthDataStreamHandlerImpl(handler!!)
        }
        if (updateStreamHandler == null) {
            updateStreamHandler = UpdateDataStreamHandlerImpl(handler!!)
        }

        Log.d(
            PLUGIN_TAG,
            "Device state stream handler sink = $deviceStateStreamHandler"
        )

        if (gson == null) {
            gson = GsonBuilder().create()
        }

        val hashCode = this.hashCode()

        Log.d(
            PLUGIN_TAG,
            "Device state stream handler sink this hashcode = $hashCode"
        )
        DevicesStreamHandler.register(flutterPluginBinding.binaryMessenger, devicesHandler!!)
        SleepDataStreamHandler.register(flutterPluginBinding.binaryMessenger, sleepDataHandler!!)
        DeviceStateStreamHandler.register(
            flutterPluginBinding.binaryMessenger,
            deviceStateStreamHandler!!
        )
        HealthDataStreamHandler.register(
            flutterPluginBinding.binaryMessenger,
            healthStreamHandler!!
        )
        AllDataStreamHandler.register(
            flutterPluginBinding.binaryMessenger,
            allStreamHandler!!
        )
        UpdateDataStreamHandler.register(flutterPluginBinding.binaryMessenger, updateStreamHandler!!)

        if (api == null) {
            api = YuchengApiImpl(
                onDevice = { device -> devicesHandler?.onDevice(device) },
                onSleepData = { data -> sleepDataHandler?.onSleepData(data) },
                sleepDataConverter = YuchengSleepDataConverter(gson!!),
                onState = { data -> deviceStateStreamHandler?.onState(data) },
                onHealthData = { data -> healthStreamHandler?.onHealth(data) },
                onAllData = { data -> allStreamHandler?.onSleepHealth(data) },
                healthDataConverter = YuchengHealthDataConverter(gson!!),
                onUpdate = {data -> updateStreamHandler?.onUpdate(data) },
                sportDataConverter = YuchengSportDataConverter(gson!!),
                assetPathHandler = { pathToFile ->
                    var path = flutterPluginBinding.flutterAssets.getAssetFilePathByName(pathToFile)
                    val cachePath = getExternalAppCachePath(flutterPluginBinding.applicationContext)
                    if (cachePath == null) {
                        return@YuchengApiImpl ""
                    }
                    val tempFileName =
                        (cachePath + "/"
                                + UUID.randomUUID().toString()) + path.takeLast(4)
                    copyFileFromAssets(path, tempFileName, flutterPluginBinding.applicationContext)
                    path = tempFileName
                    return@YuchengApiImpl path
                },
            )
        }

        YuchengHostApi.setUp(flutterPluginBinding.binaryMessenger, api)

        YCBTClient.initClient(flutterPluginBinding.applicationContext, true)
        YCBTClient.registerBleStateChange { state ->
            when (state) {
                Constants.BLEState.Connected -> {
                    deviceStateStreamHandler?.onState(
                        YuchengDeviceStateDataEvent(
                            YuchengDeviceState.CONNECTED
                        )
                    )
                }

                Constants.BLEState.TimeOut -> {
                    deviceStateStreamHandler?.onState(
                        YuchengDeviceStateDataEvent(
                            YuchengDeviceState.TIME_OUT
                        )
                    )
                }

                Constants.BLEState.Disconnect -> {
                    deviceStateStreamHandler?.onState(
                        YuchengDeviceStateDataEvent(
                            YuchengDeviceState.DISCONNECTED
                        )
                    )
                }

                Constants.BLEState.ReadWriteOK -> {
                    deviceStateStreamHandler?.onState(
                        YuchengDeviceStateDataEvent(
                            YuchengDeviceState.READ_WRITE_OK
                        )
                    )
                }

                else -> {
                    deviceStateStreamHandler?.onState(
                        YuchengDeviceStateDataEvent(
                            YuchengDeviceState.UNKNOWN
                        )
                    )
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
        healthStreamHandler?.detach()
        allStreamHandler?.detach()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activtiy = binding.activity
        if (api != null) {
            api?.activity = activtiy
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        TODO("Not yet implemented")
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activtiy = binding.activity
        if (api != null) {
            api?.activity = activtiy
        }
    }

    override fun onDetachedFromActivity() {
        activtiy = null
        if (api != null) {
            api?.activity = null
        }
    }

    companion object {
        private var api: YuchengApiImpl? = null
        private var devicesHandler: DevicesStreamHandlerImpl? = null
        private var sleepDataHandler: SleepDataHandlerImpl? = null
        private var deviceStateStreamHandler: DeviceStateStreamHandlerImpl? = null
        private var healthStreamHandler: HealthDataStreamHandlerImpl? = null
        private var allStreamHandler: AllDataStreamHandlerImpl? = null
        private var updateStreamHandler: UpdateDataStreamHandlerImpl? = null
        private var gson: Gson? = null
        private var handler: Handler? = null
        private var activtiy: Activity? = null
        val PLUGIN_TAG: String = "YuchengBlePlugin"
    }
}