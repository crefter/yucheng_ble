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
            selector: #selector(deviceStateChange(_:)),
            name: YCProduct.deviceStateNotification,
            object: nil
        )
    }
    
    @objc private func deviceStateChange(_ ntf: Notification) {
        guard let info = ntf.userInfo as? [String: Any],
              let state = info[YCProduct.connecteStateKey] as? YCProductState else {
            return
        }
        if (state == YCProductState.connected) {
            onState(YuchengDeviceStateDataEvent(state: YuchengProductState.connected))
        } else if (state == YCProductState.connectedFailed) {
            onState(YuchengDeviceStateDataEvent(state: YuchengProductState.connectedFailed))
        } else if (state == YCProductState.disconnected) {
            onState(YuchengDeviceStateDataEvent(state: YuchengProductState.disconnected))
        } else if (state == YCProductState.unavailable) {
            onState(YuchengDeviceStateDataEvent(state: YuchengProductState.unavailable))
        } else if (state == YCProductState.timeout) {
            onState(YuchengDeviceStateDataEvent(state: YuchengProductState.timeOut))
        } else if (state == YCProductState.succeed) {
            onState(YuchengDeviceStateDataEvent(state: YuchengProductState.readWriteOK))
        }
        else {
            onState(YuchengDeviceStateDataEvent(state: YuchengProductState.unknown))
        }
        print("STATE: " + state.toString)
    }
    
    private func onState(_ event: YuchengDeviceStateEvent) {
        YuchengBlePlugin.deviceStateStreamHandler?.onDeviceStateChanged(event)
    }
    
    public func detachFromEngine(for registrar: any FlutterPluginRegistrar) {
        YuchengHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
        YCProduct.stopSearchDevice()
        YuchengBlePlugin.devicesHandler?.detach()
        YuchengBlePlugin.sleepDataHandler?.detach()
        YuchengBlePlugin.deviceStateStreamHandler?.detach()
    }
}
