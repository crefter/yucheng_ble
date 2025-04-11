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
        eventSink = sink
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Devices stream handler onListen")
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Device stream handler sink = $sink")
    }

    override fun onCancel(p0: Any?) {
        eventSink = null
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Devices stream handler onCancel")
    }

    fun onDevice(device: YuchengDeviceEvent) {
        uiThreadHandler.post { eventSink?.success(device) }
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Devices stream handler onDevice")
    }

    fun detach() {
        eventSink?.endOfStream()
        eventSink = null
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Devices stream handler detach")
    }
}

class SleepDataHandlerImpl(private val uiThreadHandler: Handler) : SleepDataStreamHandler() {
    private var eventSink: PigeonEventSink<YuchengSleepEvent>? = null

    override fun onListen(p0: Any?, sink: PigeonEventSink<YuchengSleepEvent>) {
        eventSink = sink
        Log.d( YuchengBlePlugin.PLUGIN_TAG, "Sleep data handler onListen")
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Sleep data handler sink = $sink")
    }

    override fun onCancel(p0: Any?) {
        eventSink = null
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Sleep data handler onCancel")
    }

    fun onSleepData(sleepData: YuchengSleepEvent) {
        uiThreadHandler.post { eventSink?.success(sleepData) }
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Sleep data handler onSleepData")
    }

    fun detach() {
        eventSink?.endOfStream()
        eventSink = null
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Sleep data handler detach")
    }
}

class DeviceStateStreamHandlerImpl(private val uiThreadHandler: Handler) : DeviceStateStreamHandler() {
    private var eventSink: PigeonEventSink<YuchengDeviceStateEvent>? = null

    override fun onListen(p0: Any?, sink: PigeonEventSink<YuchengDeviceStateEvent>) {
        eventSink = sink
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Device state stream handler = $this")
        Log.d( YuchengBlePlugin.PLUGIN_TAG, "Device state handler onListen")
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Device state handler sink = $sink")
    }

    override fun onCancel(p0: Any?) {
        eventSink = null
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Device state handler onCancel")
    }

    fun onState(state: YuchengDeviceStateEvent) {
        uiThreadHandler.post {
            eventSink?.success(state)
        }
        if (eventSink == null) {
            Log.d(YuchengBlePlugin.PLUGIN_TAG, "Device state EVENT SINK IS NULL!")
        }
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Device state stream handler = $this")
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Device state handler onState")
    }

    fun detach() {
        eventSink?.endOfStream()
        eventSink = null
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Device state handler detach")
    }
}