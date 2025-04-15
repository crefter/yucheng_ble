package com.crefter.yuchengplugin.yucheng_ble

import DeviceStateStreamHandler
import DevicesStreamHandler
import HealthDataStreamHandler
import PigeonEventSink
import SleepDataStreamHandler
import SleepHealthDataStreamHandler
import YuchengDeviceEvent
import YuchengDeviceStateEvent
import YuchengHealthEvent
import YuchengSleepEvent
import YuchengSleepHealthEvent
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
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Device state stream handler sink onListen = $this")
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
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Device state stream handler sink onState = $this")
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Device state handler onState")
    }

    fun detach() {
        eventSink?.endOfStream()
        eventSink = null
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Device state handler detach")
    }
}

class HealthDataStreamHandlerImpl(private val uiThreadHandler: Handler) : HealthDataStreamHandler() {
    private var eventSink: PigeonEventSink<YuchengHealthEvent>? = null

    override fun onListen(p0: Any?, sink: PigeonEventSink<YuchengHealthEvent>) {
        eventSink = sink
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Health data stream handler sink onListen = $this")
        Log.d( YuchengBlePlugin.PLUGIN_TAG, "Health data handler onListen")
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Health data handler sink = $sink")
    }

    override fun onCancel(p0: Any?) {
        eventSink = null
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Health data handler onCancel")
    }

    fun onHealth(state: YuchengHealthEvent) {
        uiThreadHandler.post {
            eventSink?.success(state)
        }
        if (eventSink == null) {
            Log.d(YuchengBlePlugin.PLUGIN_TAG, "Health data EVENT SINK IS NULL!")
        }
    }

    fun detach() {
        eventSink?.endOfStream()
        eventSink = null
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Health data handler detach")
    }
}

class SleepHealthDataStreamHandlerImpl(private val uiThreadHandler: Handler) : SleepHealthDataStreamHandler() {
    private var eventSink: PigeonEventSink<YuchengSleepHealthEvent>? = null

    override fun onListen(p0: Any?, sink: PigeonEventSink<YuchengSleepHealthEvent>) {
        eventSink = sink
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Health data stream handler sink onListen = $this")
        Log.d( YuchengBlePlugin.PLUGIN_TAG, "Health data handler onListen")
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Health data handler sink = $sink")
    }

    override fun onCancel(p0: Any?) {
        eventSink = null
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Health data handler onCancel")
    }

    fun onSleepHealth(state: YuchengSleepHealthEvent) {
        uiThreadHandler.post {
            eventSink?.success(state)
        }
        if (eventSink == null) {
            Log.d(YuchengBlePlugin.PLUGIN_TAG, "Health data EVENT SINK IS NULL!")
        }
    }

    fun detach() {
        eventSink?.endOfStream()
        eventSink = null
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Health data handler detach")
    }
}