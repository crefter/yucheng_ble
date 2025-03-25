import Flutter
import UIKit

private class YuchengHostApiImpl : YuchengHostApi {
    func startScanDevices(scanTimeInSeconds: Double?) throws {
        
    }
    
    func isDeviceConnected(device: YuchengDevice, completion: @escaping (Result<Bool, any Error>) -> Void) {
        
    }
    
    func connect(device: YuchengDevice?, completion: @escaping (Result<Bool, any Error>) -> Void) {
        
    }
    
    func disconnect(completion: @escaping (Result<Void, any Error>) -> Void) {
        
    }
    
    func getSleepData(completion: @escaping (Result<[YuchengSleepDataEvent?], any Error>) -> Void) {
        
    }
    
    func getCurrentConnectedDevice(completion: @escaping (Result<YuchengDevice?, any Error>) -> Void) {
        
    }
    
}

private class DeviceStateStreamHandlerImpl : DeviceStateStreamHandler {
    private var eventSink: PigeonEventSink<YuchengProductStateEvent>? = nil;
    
    override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<any YuchengProductStateEvent>) {
        eventSink = sink;
    }
    override func onCancel(withArguments arguments: Any?) {
        eventSink = nil;
    }
    
    func onDeviceStateChanged(_ event: YuchengProductStateEvent) {
        eventSink?.success(event);
    }
}

private class DeviceStreamHandlerImpl : DevicesStreamHandler {
    private var eventSink: PigeonEventSink<YuchengDeviceEvent>? = nil;
    
    override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<any YuchengDeviceEvent>) {
        eventSink = sink;
    }
    
    override func onCancel(withArguments arguments: Any?) {
        eventSink = nil;
    }
    
    func onDeviceChanged(_ event: YuchengDeviceEvent) {
        eventSink?.success(event);
    }
}

private class SleepDataHandlerImpl : SleepDataStreamHandler {
    private var eventSink: PigeonEventSink<YuchengSleepDataEvent>? = nil;

    
    override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<YuchengSleepDataEvent>) {
        eventSink = sink;
    }
    
    override func onCancel(withArguments arguments: Any?) {
        eventSink = nil;
    }
    
    func onSleepDataChanged(_ event: YuchengSleepDataEvent) {
        eventSink?.success(event);
    }
}


public class YuchengBlePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "yucheng_ble", binaryMessenger: registrar.messenger())
    let instance = YuchengBlePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
