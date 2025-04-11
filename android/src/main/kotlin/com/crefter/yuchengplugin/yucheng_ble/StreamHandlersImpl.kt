package com.crefter.yuchengplugin.yucheng_ble

import DeviceStateStreamHandler
import DevicesStreamHandler
import PigeonEventSink
import SleepDataStreamHandler
import YuchengDeviceEvent
import YuchengDeviceStateEvent
import YuchengSleepEvent
import android.os.Handler
import android.util.Log

class DevicesStreamHandlerImpl(private val uiThreadHandler: Handler) : DevicesStreamHandler() {
    private var eventSink: PigeonEventSink<YuchengDeviceEvent>? = null

    override fun onListen(p0: Any?, sink: PigeonEventSink<YuchengDeviceEvent>) {
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Devices stream handler onListen")
        eventSink = sink
    }

    override fun onCancel(p0: Any?) {
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Devices stream handler onCancel")
        eventSink = null
    }

    fun onDevice(device: YuchengDeviceEvent) {
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Devices stream handler onDevice")
        uiThreadHandler.post { eventSink?.success(device) }
    }
}

class SleepDataHandlerImpl(private val uiThreadHandler: Handler) : SleepDataStreamHandler() {
    private var eventSink: PigeonEventSink<YuchengSleepEvent>? = null

    override fun onListen(p0: Any?, sink: PigeonEventSink<YuchengSleepEvent>) {
        Log.d( YuchengBlePlugin.PLUGIN_TAG, "Sleep data handler onListen")
        eventSink = sink
    }

    override fun onCancel(p0: Any?) {
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Sleep data handler onCancel")
        eventSink = null
    }

    fun onSleepData(sleepData: YuchengSleepEvent) {
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Sleep data handler onSleepData")
        uiThreadHandler.post { eventSink?.success(sleepData) }
    }
}

class DeviceStateStreamHandlerImpl(private val uiThreadHandler: Handler) : DeviceStateStreamHandler() {
    private var eventSink: PigeonEventSink<YuchengDeviceStateEvent>? = null

    override fun onListen(p0: Any?, sink: PigeonEventSink<YuchengDeviceStateEvent>) {
        Log.d( YuchengBlePlugin.PLUGIN_TAG, "Device state handler onListen")
        eventSink = sink
    }

    override fun onCancel(p0: Any?) {
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Device state handler onCancel")
        eventSink = null
    }

    fun onState(state: YuchengDeviceStateEvent) {
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Device state handler onState")
        uiThreadHandler.post { eventSink?.success(state) }
    }
}