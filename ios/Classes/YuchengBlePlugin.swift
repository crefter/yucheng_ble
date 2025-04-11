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

        if (devicesHandler == nil) {
            devicesHandler = DeviceStreamHandlerImpl();
        }
        if (sleepDataHandler == nil) {
            sleepDataHandler = SleepDataHandlerImpl();
        }
        if (deviceStateStreamHandler == nil) {
            deviceStateStreamHandler = DeviceStateStreamHandlerImpl();
        }
        
        DevicesStreamHandler.register(with: registrar.messenger(), streamHandler: devicesHandler!)
        SleepDataStreamHandler.register(with: registrar.messenger(), streamHandler: sleepDataHandler!)
        DeviceStateStreamHandler.register(with: registrar.messenger(), streamHandler: deviceStateStreamHandler!)
        
        if (api == nil) {
            api = YuchengHostApiImpl(onDevice: { event in
                devicesHandler?.onDeviceChanged(event)
            }, onSleepData: { event in
                sleepDataHandler?.onSleepDataChanged(event)
            }, converter: converter)
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
            YuchengBlePlugin.deviceStateStreamHandler?.onDeviceStateChanged(YuchengDeviceStateDataEvent(state: YuchengProductState.connected))
        } else if (state == YCProductState.connectedFailed) {
            YuchengBlePlugin.deviceStateStreamHandler?.onDeviceStateChanged(YuchengDeviceStateDataEvent(state: YuchengProductState.connectedFailed))
        } else if (state == YCProductState.disconnected) {
            YuchengBlePlugin.deviceStateStreamHandler?.onDeviceStateChanged(YuchengDeviceStateDataEvent(state: YuchengProductState.disconnected))
        } else if (state == YCProductState.unavailable) {
            YuchengBlePlugin.deviceStateStreamHandler?.onDeviceStateChanged(YuchengDeviceStateDataEvent(state: YuchengProductState.unavailable))
        } else if (state == YCProductState.timeout) {
            YuchengBlePlugin.deviceStateStreamHandler?.onDeviceStateChanged(YuchengDeviceStateDataEvent(state: YuchengProductState.timeOut))
        } else if (state == YCProductState.succeed) {
            YuchengBlePlugin.deviceStateStreamHandler?.onDeviceStateChanged(YuchengDeviceStateDataEvent(state: YuchengProductState.readWriteOK))
        } else {
            YuchengBlePlugin.deviceStateStreamHandler?.onDeviceStateChanged(YuchengDeviceStateDataEvent(state: YuchengProductState.unknown))
        }
        print("STATE: " + state.toString)
    }
    
    public func detachFromEngine(for registrar: any FlutterPluginRegistrar) {
        YuchengHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
        YCProduct.stopSearchDevice()
        YuchengBlePlugin.devicesHandler?.detach()
        YuchengBlePlugin.sleepDataHandler?.detach()
        YuchengBlePlugin.deviceStateStreamHandler?.detach()
    }
}
