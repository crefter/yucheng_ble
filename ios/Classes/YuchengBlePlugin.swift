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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.deviceStateChange(_:)),
            name: YCProduct.deviceStateNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(receiveRealTimeData(_:)),
            name: YCProduct.receivedRealTimeNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceDataStateChanged(_:)),
            name: YCProduct.deviceControlNotification,
            object: nil
        )
    }
    
    @objc class func deviceDataStateChanged(_ ntf: Notification) {
        guard let info = ntf.userInfo else {
            return
        }
        if let response = info[YCDeviceControlType.healthDataMeasurementResult.toString] as?
            YCReceivedDeviceReportInfo,
           let device = response.device,
           let data = response.data as? YCDeviceControlMeasureHealthDataResultInfo {
            let state = data.state
            let type = data.dataType
            if (type == YCAppControlMeasureHealthDataType.bloodPressure) {
                YuchengBlePlugin.api!.bloodPressureCompleter?.complete(true)
            } else if (type == YCAppControlMeasureHealthDataType.bloodOxygen) {
                YuchengBlePlugin.api!.bloodOxygenCompleter?.complete(true)
            }
            let description = data.description
            print("CONTROL DATA RESULT",device.name ?? "",
                  state,
                  type,
                  description
            )
        }
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
    
    @objc class func receiveRealTimeData(_ notification: Notification) {
        guard let info = notification.userInfo else {
            return
        }
        if let response = info[YCReceivedRealTimeDataType.step.toString] as?
            YCReceivedDeviceReportInfo,
           let device = response.device,
           let sportInfo = response.data as? YCReceivedRealTimeStepInfo {
            print("STEPS", device.name ?? ""
                  ,
                  sportInfo.step,
                  sportInfo.calories,
                  sportInfo.distance
            )
            YuchengBlePlugin.api?.setSteps(steps: Int64(sportInfo.step))
            YuchengBlePlugin.api?.setCalories(calories: Int64(sportInfo.calories))
            YuchengBlePlugin.api?.setDistance(distance: Int64(sportInfo.distance))
        }
        if let response =
            info[YCReceivedRealTimeDataType.realTimeMonitoringMode.toString] as?
            YCReceivedDeviceReportInfo {
           let device = response.device
            print("REAL TIME MONITORING MODE", response.data)
               if let data = response.data as? YCReceivedMonitoringModeInfo {
                   print("MODE:", device?.name ?? "",
                         data.startTimeStamp,
                         data.modeStep,
                         data.modeCalories,
                         data.modeCalories
                   )
               }
        }
        // Blood pressure data
        if let response =
            info[YCReceivedRealTimeDataType.bloodPressure.toString] as?
            YCReceivedDeviceReportInfo
        {
            let device = response.device
            if let healthData = response.data as? YCReceivedRealTimeBloodPressureInfo {
                let heartRate = healthData.heartRate
                let systolicBloodPressure =
                healthData.systolicBloodPressure
                let diastolicBloodPressure =
                healthData.diastolicBloodPressure
                print("BLOOD PRESSURE", device?.name ?? "",
                      heartRate,
                      systolicBloodPressure,
                      diastolicBloodPressure
                )
                YuchengBlePlugin.api?.heartRates.append(Int64(heartRate))
                YuchengBlePlugin.api?.dbps.append(Int64(diastolicBloodPressure))
                YuchengBlePlugin.api?.sbps.append(Int64(systolicBloodPressure))
            }
        }
        if let response =
            info[YCReceivedRealTimeDataType.bloodOxygen.toString] as?
            YCReceivedDeviceReportInfo
        {
            let device = response.device
            let data = response.data
            if (data != nil) {
                let dataString = String(describing: data!)
                let bloodOxygen = Int64(dataString) ?? 0
                YuchengBlePlugin.api?.bloodOxygens.append(bloodOxygen)
                print("BLOOD OXYGEN INT", device?.name ?? "",
                      response.data ?? "no blood oxygen data"
                )
            }
        }
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
