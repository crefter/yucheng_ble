package com.crefter.yuchengplugin.yucheng_ble

import DeviceStateStreamHandler
import DevicesStreamHandler
import PigeonEventSink
import SleepDataStreamHandler
import YuchengDeviceEvent
import YuchengProductStateEvent
import YuchengSleepEvent
import android.util.Log

class DevicesStreamHandlerImpl : DevicesStreamHandler() {
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
        eventSink?.success(device)
    }

    fun detach() {
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Devices stream handler detach")
        eventSink?.endOfStream()
        eventSink = null
    }
}

class SleepDataHandlerImpl : SleepDataStreamHandler() {
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
        eventSink?.success(sleepData)
    }

    fun detach() {
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Sleep data handler detach")
        eventSink?.endOfStream()
        eventSink = null
    }
}

class DeviceStateStreamHandlerImpl : DeviceStateStreamHandler() {
    private var eventSink: PigeonEventSink<YuchengProductStateEvent>? = null

    override fun onListen(p0: Any?, sink: PigeonEventSink<YuchengProductStateEvent>) {
        Log.d( YuchengBlePlugin.PLUGIN_TAG, "Sleep data handler onListen")
        eventSink = sink
    }

    override fun onCancel(p0: Any?) {
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Sleep data handler onCancel")
        eventSink = null
    }

    fun onState(state: YuchengProductStateEvent) {
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Sleep data handler onSleepData")
        eventSink?.success(state)
    }

    fun detach() {
        Log.d(YuchengBlePlugin.PLUGIN_TAG, "Sleep data handler detach")
        eventSink?.endOfStream()
        eventSink = null
    }
}