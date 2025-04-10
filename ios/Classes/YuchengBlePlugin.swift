import Flutter
import UIKit
import CoreBluetooth
import YCProductSDK

public class YuchengBlePlugin: NSObject, FlutterPlugin {
    private static var api: YuchengHostApi? = nil
    private static var devicesHandler: DeviceStreamHandlerImpl? = nil
    private static var sleepDataHandler: SleepDataHandlerImpl? = nil
    private static var deviceStateStreamHandler: DeviceStateStreamHandlerImpl? = nil
    private static let converter = YuchengSleepDataConverter()
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        print("Register 1")
        devicesHandler = DeviceStreamHandlerImpl();
        sleepDataHandler = SleepDataHandlerImpl();
        deviceStateStreamHandler = DeviceStateStreamHandlerImpl();
        
        print("Register 0")
        _ = YCProduct.shared;
        
        print("Register 2")
        
        DevicesStreamHandler.register(with: registrar.messenger(), streamHandler: devicesHandler!)
        SleepDataStreamHandler.register(with: registrar.messenger(), streamHandler: sleepDataHandler!)
        DeviceStateStreamHandler.register(with: registrar.messenger(), streamHandler: deviceStateStreamHandler!)
        
        print("Register 3")
        
        api = YuchengHostApiImpl(onDevice: { event in
            devicesHandler?.onDeviceChanged(event)
        }, onSleepData: { event in
            sleepDataHandler?.onSleepDataChanged(event)
        }, onState: { event in
            deviceStateStreamHandler?.onDeviceStateChanged(event)
        }, converter: converter)
        
        print("Register 4")
        
        YuchengHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: api!)
        print("Register 5")
    }
    
    public func detachFromEngine(for registrar: any FlutterPluginRegistrar) {
        YuchengHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
        YCProduct.stopSearchDevice()
        YuchengBlePlugin.devicesHandler?.detach()
        YuchengBlePlugin.sleepDataHandler?.detach()
        YuchengBlePlugin.deviceStateStreamHandler?.detach()
    }
}
