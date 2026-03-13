package com.crefter.yuchengplugin.yucheng_ble

import android.app.Activity
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import com.crefter.yuchengplugin.yucheng_ble.PathUtils.getExternalAppCachePath
import com.crefter.yuchengplugin.yucheng_ble.ResourceUtils.copyFileFromAssets
import com.crefter.yuchengplugin.yucheng_ble.service.YuchengBleService
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import com.yucheng.ycbtsdk.Constants
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.UUID


/** YuchengBlePlugin */
class YuchengBlePlugin : FlutterPlugin, ActivityAware {
    private var activity: Activity? = null
    // TODO: потестить просто и в sleeptery (добавить кнопку в девайсе для запуска и отключения сервиса)

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
        YuchengCore.addListenerState(listener = { state -> stateListener(state) })
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
        Log.e(PLUGIN_TAG, "onDetachedFromEngine")
        YuchengHostApi.setUp(binding.binaryMessenger, null)
        YuchengCore.removeListenerState(listener = { state -> stateListener(state) })
        YuchengCore.dispose()
        devicesHandler?.detach()
        sleepDataHandler?.detach()
        deviceStateStreamHandler?.detach()
        healthStreamHandler?.detach()
        allStreamHandler?.detach()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        Log.e(PLUGIN_TAG, "onAttachedToActivity")
        activity = binding.activity
        if (api != null) {
            api?.activity = activity
        }
        if (activity != null) {
            if (YuchengCore.isConnected()) {
                Log.e(PLUGIN_TAG, "onAttachedToActivity: disconnect!")
                YuchengCore.disconnect()
            }
            if (ActivityCompat.checkSelfPermission(
                    activity!!,
                    android.Manifest.permission.POST_NOTIFICATIONS
                ) == PackageManager.PERMISSION_GRANTED
            ) {
                Log.e(PLUGIN_TAG, "onAttachedToActivity: permission granted!")
                CoroutineScope(Dispatchers.Main).launch {
                    val serviceOn = YuchengCore.storage?.readServiceOn() ?: false
                    if (serviceOn) {
                        Log.e(PLUGIN_TAG, "onAttachedToActivity: Service on, start!")
                        YuchengBleService.restartService(activity!!)
                    } else {
                        Log.e(PLUGIN_TAG, "onAttachedToActivity: Service off, cant start!")
                    }
                }
            } else {
                Log.e(PLUGIN_TAG, "onAttachedToActivity: NO PERMISSION!")
            }
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        Log.e(PLUGIN_TAG, "onDetachedFromActivityForConfigChanges")
        activity = null
        if (api != null) {
            api?.activity = null
        }
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        Log.e(PLUGIN_TAG, "onReattachedToActivityForConfigChanges")
        activity = binding.activity
        if (api != null) {
            api?.activity = activity
        }
        if (activity != null) {
            YuchengBleService.stopService(activity!!)
        }
    }

    override fun onDetachedFromActivity() {
        Log.e(PLUGIN_TAG, "onDetachedFromActivity: start")
        activity = null
        if (api != null) {
            api?.activity = null
        }
        Log.e(PLUGIN_TAG, "onDetachedFromActivity: end")
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