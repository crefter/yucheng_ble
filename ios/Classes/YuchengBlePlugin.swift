import Flutter
import UIKit
import CoreBluetooth
import YCProductSDK

public class YuchengBlePlugin: NSObject, FlutterPlugin {
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
        
        //         YCProduct.realTimeDataUplod(YCProduct.shared.currentPeripheral,
        //                                             isEnable: true,
        //                                             dataType: YCRealTimeDataType.combinedData,
        //                                             completion: {state, result in
        //                     if state == .succeed {
        //
        //                     } else {
        //
        //                     }
        //                 } );
        
        DevicesStreamHandler.register(with: registrar.messenger(), streamHandler: devicesHandler!)
        SleepDataStreamHandler.register(with: registrar.messenger(), streamHandler: sleepDataHandler!)
        DeviceStateStreamHandler.register(with: registrar.messenger(), streamHandler: deviceStateStreamHandler!)
        AllDataStreamHandler.register(with: registrar.messenger(), streamHandler: allDataHandler!)
        HealthDataStreamHandler.register(with: registrar.messenger(), streamHandler: healthDataHandler!)
        UpdateDataStreamHandler.register(with: registrar.messenger(), streamHandler: updateStreamHandler!)
        
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
        
        _ = YCProduct.shared;
    }
    
    public func detachFromEngine(for registrar: any FlutterPluginRegistrar) {
        YuchengHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
        YCProduct.stopSearchDevice()
        YuchengBlePlugin.devicesHandler?.detach()
        YuchengBlePlugin.sleepDataHandler?.detach()
        YuchengBlePlugin.deviceStateStreamHandler?.detach()
        YuchengBlePlugin.healthDataHandler?.detach()
        YuchengBlePlugin.allDataHandler?.detach()
    }
}
