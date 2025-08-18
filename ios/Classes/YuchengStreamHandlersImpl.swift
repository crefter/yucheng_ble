//
//  YuchengStreamHandlersImpl.swift
//  Pods
//
//  Created by Maxim Zarechnev on 10.04.2025.
//
import YCProductSDK
import Flutter
import CoreBluetooth

class DeviceStateStreamHandlerImpl : DeviceStateStreamHandler {
    private var eventSink: PigeonEventSink<YuchengDeviceStateEvent>? = nil;
    
    override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<any YuchengDeviceStateEvent>) {
        eventSink = sink;
    }
    override func onCancel(withArguments arguments: Any?) {
        eventSink = nil;
    }
    
    func onDeviceStateChanged(_ event: YuchengDeviceStateEvent) {
        print("onDeviceStateChanged = new event")
        eventSink?.success(event);
    }
    
    func detach() {
        eventSink?.endOfStream()
        eventSink = nil;
    }
}

class DeviceStreamHandlerImpl : DevicesStreamHandler {
    private var eventSink: PigeonEventSink<YuchengDeviceEvent>? = nil;
    
    override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<any YuchengDeviceEvent>) {
        eventSink = sink;
    }
    
    override func onCancel(withArguments arguments: Any?) {
        eventSink = nil;
    }
    
    func onDeviceChanged(_ event: YuchengDeviceEvent) {
        print("onDeviceChanged = new event")
        eventSink?.success(event);
    }
    
    func detach() {
        eventSink?.endOfStream()
        eventSink = nil;
    }
}

class SleepDataHandlerImpl : SleepDataStreamHandler {
    private var eventSink: PigeonEventSink<YuchengSleepEvent>? = nil;
    
    
    override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<YuchengSleepEvent>) {
        eventSink = sink;
    }
    
    override func onCancel(withArguments arguments: Any?) {
        eventSink = nil;
    }
    
    func onSleepDataChanged(_ event: YuchengSleepEvent) {
        print("onSleepDataChanged = new event")
        eventSink?.success(event);
    }
    
    func detach() {
        eventSink?.endOfStream()
        eventSink = nil;
    }
}

class HealthDataHandlerImpl : HealthDataStreamHandler {
    private var eventSink: PigeonEventSink<YuchengHealthEvent>? = nil;
    
    
    override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<YuchengHealthEvent>) {
        eventSink = sink;
    }
    
    override func onCancel(withArguments arguments: Any?) {
        eventSink = nil;
    }
    
    func onHealth(_ event: YuchengHealthEvent) {
        print("onHealth = new event")
        eventSink?.success(event);
    }
    
    func detach() {
        eventSink?.endOfStream()
        eventSink = nil;
    }
}

class AllDataStreamHandlerImpl : AllDataStreamHandler {
    private var eventSink: PigeonEventSink<YuchengAllEvent>? = nil;
    
    
    override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<YuchengAllEvent>) {
        eventSink = sink;
    }
    
    override func onCancel(withArguments arguments: Any?) {
        eventSink = nil;
    }
    
    func onAllDataChanged(_ event: YuchengAllEvent) {
        print("onAllDataChanged = new event")
        eventSink?.success(event);
    }
    
    func detach() {
        eventSink?.endOfStream()
        eventSink = nil;
    }
}

class UpdateDataHandlerImpl : UpdateDataStreamHandler {
    private var eventSink: PigeonEventSink<YuchengUpdateEvent>? = nil;
    
    
    override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<YuchengUpdateEvent>) {
        eventSink = sink;
    }
    
    override func onCancel(withArguments arguments: Any?) {
        eventSink = nil;
    }
    
    func onUpdateChanged(_ event: YuchengUpdateEvent) {
        print("onUpdateData = new event")
        eventSink?.success(event);
    }
    
    func detach() {
        eventSink?.endOfStream()
        eventSink = nil;
    }
}
