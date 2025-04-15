import Flutter
import UIKit
import CoreBluetooth
import YCProductSDK

public class YuchengBlePlugin: NSObject, FlutterPlugin {
    private static var api: YuchengHostApi? = nil
    private static var devicesHandler: DeviceStreamHandlerImpl? = nil
    private static var sleepDataHandler: SleepDataHandlerImpl? = nil
    private static var healthDataHandler: HealthDataHandlerImpl? = nil
    private static var sleepHealthDataHandler: SleepHealthDataHandlerImpl? = nil
    private static var deviceStateStreamHandler: DeviceStateStreamHandlerImpl? = nil
    
    private static let sleepConverter = YuchengSleepDataConverter()
    private static let healthConverter = YuchengHealthDataConverter()
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        
        if (devicesHandler == nil) {
            devicesHandler = DeviceStreamHandlerImpl();
        }
        if (sleepDataHandler == nil) {
            sleepDataHandler = SleepDataHandlerImpl();
        }
        if (deviceStateStreamHandler == nil) {
            deviceStateStreamHandler = DeviceStateStreamHandlerImpl();
        }
        if (sleepHealthDataHandler == nil) {
            sleepHealthDataHandler = SleepHealthDataHandlerImpl();
        }
        if (healthDataHandler == nil) {
            healthDataHandler = HealthDataHandlerImpl()
        }
        
        DevicesStreamHandler.register(with: registrar.messenger(), streamHandler: devicesHandler!)
        SleepDataStreamHandler.register(with: registrar.messenger(), streamHandler: sleepDataHandler!)
        DeviceStateStreamHandler.register(with: registrar.messenger(), streamHandler: deviceStateStreamHandler!)
        SleepHealthDataStreamHandler.register(with: registrar.messenger(), streamHandler: sleepHealthDataHandler!)
        HealthDataStreamHandler.register(with: registrar.messenger(), streamHandler: healthDataHandler!)
        
        if (api == nil) {
            api = YuchengHostApiImpl(
                onDevice: { event in
                    devicesHandler?.onDeviceChanged(event)
                },
                onSleepData: { event in
                    sleepDataHandler?.onSleepDataChanged(event)
                },
                onState: {event in deviceStateStreamHandler?.onDeviceStateChanged(event)},
                onHealth: {event in healthDataHandler?.onHealth(event)},
                onSleepHealth: {event in sleepHealthDataHandler?.onSleepDataChanged(event)},
                sleepConverter: sleepConverter,
                healthConverter: healthConverter)
        }
        
        YuchengHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: api!)
        
        _ = YCProduct.shared;
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.deviceStateChange(_:)),
            name: YCProduct.deviceStateNotification,
            object: nil
        )
    }
    
    @objc class func deviceStateChange(_ ntf: Notification) {
        guard let info = ntf.userInfo as? [String: Any],
              let state = info[YCProduct.connecteStateKey] as? YCProductState else {
            return
        }
        if (state == YCProductState.connected) {
            YuchengBlePlugin.deviceStateStreamHandler?.onDeviceStateChanged(YuchengDeviceStateDataEvent(state: YuchengDeviceState.connected))
        } else if (state == YCProductState.connectedFailed) {
            YuchengBlePlugin.deviceStateStreamHandler?.onDeviceStateChanged(YuchengDeviceStateDataEvent(state: YuchengDeviceState.connectedFailed))
        } else if (state == YCProductState.disconnected) {
            YuchengBlePlugin.deviceStateStreamHandler?.onDeviceStateChanged(YuchengDeviceStateDataEvent(state: YuchengDeviceState.disconnected))
        } else if (state == YCProductState.unavailable) {
            YuchengBlePlugin.deviceStateStreamHandler?.onDeviceStateChanged(YuchengDeviceStateDataEvent(state: YuchengDeviceState.unavailable))
        } else if (state == YCProductState.timeout) {
            YuchengBlePlugin.deviceStateStreamHandler?.onDeviceStateChanged(YuchengDeviceStateDataEvent(state: YuchengDeviceState.timeOut))
        } else if (state == YCProductState.succeed) {
            YuchengBlePlugin.deviceStateStreamHandler?.onDeviceStateChanged(YuchengDeviceStateDataEvent(state: YuchengDeviceState.readWriteOK))
        } else {
            YuchengBlePlugin.deviceStateStreamHandler?.onDeviceStateChanged(YuchengDeviceStateDataEvent(state: YuchengDeviceState.unknown))
        }
        print("STATE: " + state.toString)
    }
    
    public func detachFromEngine(for registrar: any FlutterPluginRegistrar) {
        YuchengHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
        YCProduct.stopSearchDevice()
        YuchengBlePlugin.devicesHandler?.detach()
        YuchengBlePlugin.sleepDataHandler?.detach()
        YuchengBlePlugin.deviceStateStreamHandler?.detach()
        YuchengBlePlugin.healthDataHandler?.detach()
        YuchengBlePlugin.sleepHealthDataHandler?.detach()
    }
}
