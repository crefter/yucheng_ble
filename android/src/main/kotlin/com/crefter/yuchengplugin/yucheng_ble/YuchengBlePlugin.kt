package com.crefter.yuchengplugin.yucheng_ble

import DeviceStateStreamHandler
import DevicesStreamHandler
import SleepDataStreamHandler
import YuchengDeviceStateDataEvent
import YuchengHostApi
import android.Manifest
import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.crefter.yuchengplugin.yucheng_ble.PathUtils.getExternalAppCachePath
import com.crefter.yuchengplugin.yucheng_ble.ResourceUtils.copyFileFromAssets
import com.crefter.yuchengplugin.yucheng_ble.service.YuchengBleService
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import com.yucheng.ycbtsdk.Constants
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import java.util.UUID


/** YuchengBlePlugin */
class YuchengBlePlugin : FlutterPlugin, ActivityAware {
    private var activity: Activity? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(PLUGIN_TAG, "Start attaching to engine")
        if (handler == null) {
            handler = Handler(Looper.getMainLooper())
        }
        YuchengCore.init(flutterPluginBinding.applicationContext)
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
        UpdateDataStreamHandler.register(
            flutterPluginBinding.binaryMessenger,
            updateStreamHandler!!
        )

        if (api == null) {
            api = YuchengApiImpl(
                onDevice = { device -> devicesHandler?.onDevice(device) },
                onSleepData = { data -> sleepDataHandler?.onSleepData(data) },
                sleepDataConverter = YuchengSleepDataConverter(gson!!),
                onState = { data -> deviceStateStreamHandler?.onState(data) },
                onHealthData = { data -> healthStreamHandler?.onHealth(data) },
                onAllData = { data -> allStreamHandler?.onSleepHealth(data) },
                healthDataConverter = YuchengHealthDataConverter(gson!!),
                onUpdate = { data -> updateStreamHandler?.onUpdate(data) },
                sportDataConverter = YuchengSportDataConverter(gson!!),
                assetPathHandler = { pathToFile ->
                    var path = flutterPluginBinding.flutterAssets.getAssetFilePathByName(pathToFile)
                    val cachePath = getExternalAppCachePath(flutterPluginBinding.applicationContext)
                        ?: return@YuchengApiImpl ""
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
        YuchengCore.addListenerState(listener = {state -> stateListener(state)})
    }

    fun stateListener(state: Int) {
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

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        YuchengHostApi.setUp(binding.binaryMessenger, null)
        YuchengCore.removeListenerState(listener = {state -> stateListener(state)})
        YuchengCore.dispose()
        devicesHandler?.detach()
        sleepDataHandler?.detach()
        deviceStateStreamHandler?.detach()
        healthStreamHandler?.detach()
        allStreamHandler?.detach()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        if (api != null) {
            api?.activity = activity
        }
        // TODO: нужно запрашивать разрешение
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityCompat.requestPermissions(
                activity!!,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                1
            )
        }
        // TODO: останавливаем сервис при аттаче
        if (activity != null) {
            val intent = Intent(activity!!, YuchengBleService::class.java)
            intent.action = "STOP_SERVICE"
            activity!!.startService(intent)
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
        if (api != null) {
            api?.activity = null
        }
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        if (api != null) {
            api?.activity = activity
        }
    }

    override fun onDetachedFromActivity() {
        // TODO: запускаем сервис при detach
        if (activity != null) {
            val intent = Intent(activity, YuchengBleService::class.java)
            ContextCompat.startForegroundService(activity!!, intent)
        }
        activity = null
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
        val PLUGIN_TAG: String = "YuchengBlePlugin"
    }
}