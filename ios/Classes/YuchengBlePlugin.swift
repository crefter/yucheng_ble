import Flutter
import UIKit
import CoreBluetooth
import YCProductSDK

public class YuchengBlePlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
    private var diagnosticsChannel: FlutterMethodChannel?
    private static var api: YuchengHostApiImpl? = nil
    private static var devicesHandler: DeviceStreamHandlerImpl? = nil
    private static var sleepDataHandler: SleepDataHandlerImpl? = nil
    private static var healthDataHandler: HealthDataHandlerImpl? = nil
    private static var allDataHandler: AllDataStreamHandlerImpl? = nil
    private static var deviceStateStreamHandler: DeviceStateStreamHandlerImpl? = nil
    private static var updateStreamHandler: UpdateDataHandlerImpl? = nil
    
    private static let sleepConverter = YuchengSleepDataConverter()
    private static let healthConverter = YuchengHealthDataConverter()
    private static let sportDataConverter = YuchengSportDataConverter()
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = YuchengBlePlugin()
        let diagnosticsChannel = FlutterMethodChannel(name: "yucheng_ble/diagnostics",
            binaryMessenger: registrar.messenger())
        diagnosticsChannel.setMethodCallHandler { call, result in
            switch call.method {
            case "setDetailedEnabled":
                guard let enabled = call.arguments as? Bool else {
                    result(FlutterError(code: "invalid_argument", message: "Expected a boolean", details: nil))
                    return
                }
                YuchengDiagnostics.shared.setDetailedEnabled(enabled) { result($0) }
            case "flush":
                YuchengDiagnostics.shared.flush { result($0) }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        instance.diagnosticsChannel = diagnosticsChannel
        YuchengDiagnostics.shared.summary("engine_attached")
        registrar.addApplicationDelegate(instance)
        registrar.addSceneDelegate(instance)
        if (devicesHandler == nil) {
            devicesHandler = DeviceStreamHandlerImpl();
        }
        if (sleepDataHandler == nil) {
            sleepDataHandler = SleepDataHandlerImpl();
        }
        if (deviceStateStreamHandler == nil) {
            deviceStateStreamHandler = DeviceStateStreamHandlerImpl();
        }
        if (allDataHandler == nil) {
            allDataHandler = AllDataStreamHandlerImpl();
        }
        if (healthDataHandler == nil) {
            healthDataHandler = HealthDataHandlerImpl()
        }
        if (updateStreamHandler == nil) {
            updateStreamHandler = UpdateDataHandlerImpl()
        }
        
        DevicesStreamHandler.register(with: registrar.messenger(), streamHandler: devicesHandler!)
        SleepDataStreamHandler.register(with: registrar.messenger(), streamHandler: sleepDataHandler!)
        DeviceStateStreamHandler.register(with: registrar.messenger(), streamHandler: deviceStateStreamHandler!)
        AllDataStreamHandler.register(with: registrar.messenger(), streamHandler: allDataHandler!)
        HealthDataStreamHandler.register(with: registrar.messenger(), streamHandler: healthDataHandler!)
        UpdateDataStreamHandler.register(with: registrar.messenger(), streamHandler: updateStreamHandler!)
        
        YuchengCore.shared.initialize { state in
            deviceStateStreamHandler?.onDeviceStateChanged(state)
        } onDevice: { device in
            devicesHandler?.onDeviceChanged(device)
        }

        
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
                onAllData: {event in allDataHandler?.onAllDataChanged(event)},
                sleepConverter: sleepConverter,
                healthConverter: healthConverter,
                sportConverter: sportDataConverter,
                assetPathHandler: { pathToFile in
                    let key = registrar.lookupKey(forAsset: pathToFile)
                    let mainBundle = Bundle.main
                    let path = mainBundle.path(forResource: key, ofType: nil)
                    return path ?? ""
                },
                onUpdate: { event in updateStreamHandler?.onUpdateChanged(event)}
            )
        }
        
        YuchengHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: api!)
        
        YCProduct.setLogLevel(.off, saveLevel: .off)
        _ = YCProduct.shared;
    }
    
    public func detachFromEngine(for registrar: any FlutterPluginRegistrar) {
        YuchengDiagnostics.shared.summary("engine_detached")
        diagnosticsChannel?.setMethodCallHandler(nil)
        diagnosticsChannel = nil
        YuchengHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
        YCProduct.stopSearchDevice()
        YuchengBlePlugin.devicesHandler?.detach()
        YuchengBlePlugin.sleepDataHandler?.detach()
        YuchengBlePlugin.deviceStateStreamHandler?.detach()
        YuchengBlePlugin.healthDataHandler?.detach()
        YuchengBlePlugin.allDataHandler?.detach()
    }
    
    public func sceneDidBecomeActive(_ scene: UIScene) {
        YuchengDiagnostics.shared.summary("app_active")
    }
    
    public func sceneWillResignActive(_ scene: UIScene) {
        YuchengDiagnostics.shared.summary("app_inactive")
    }
    
    public func sceneDidDisconnect(_ scene: UIScene) {
        YuchengDiagnostics.shared.summary("scene_disconnected")
    }
    
    public func sceneDidEnterBackground(_ scene: UIScene) {
        YuchengDiagnostics.shared.summary("app_background")
    }
    
    public func sceneWillEnterForeground(_ scene: UIScene) {
        YuchengDiagnostics.shared.summary("app_foreground")
    }
}
