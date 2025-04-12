//
//  YuchengHostApiImpl.swift
//  Pods
//
//  Created by Maxim Zarechnev on 10.04.2025.
//
import YCProductSDK
import CoreBluetooth
import Flutter

enum UnimplementedError : Error {
    case notImplemented(String)
}

enum NoDeviceError : Error {
    case noDevice(String)
}


class YuchengHostApiImpl : YuchengHostApi {
   private let onDevice: (_: YuchengDeviceEvent) -> Void;
   private let onSleepData: (_: YuchengSleepEvent) -> Void;
   private let onState: (_: YuchengDeviceStateEvent) -> Void;
   private let converter: YuchengSleepDataConverter;
   private var scannedDevices: [CBPeripheral] = [];
   private var currentDevice: CBPeripheral? = nil;
   private var sleepData: [YuchengSleepDataEvent] = [];
   private var index: Int = 0;
    private let TIME_TO_TIMEOUT = 15.0;
    private let TIME_TO_SCAN = 14.0;
   
    init(onDevice: @escaping (_: YuchengDeviceEvent) -> Void, onSleepData: @escaping (_: YuchengSleepEvent) -> Void, onState: @escaping (_: YuchengDeviceStateEvent) -> Void, converter: YuchengSleepDataConverter) {
       self.onDevice = onDevice
       self.onSleepData = onSleepData
       self.converter = converter
       self.onState = onState
       DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: {
           var currentDevice: CBPeripheral? = YCProduct.shared.currentPeripheral;
           if (currentDevice != nil) {
               onState(YuchengDeviceStateDataEvent(state: .readWriteOK))
           }
       })
   }
   
   func startScanDevices(scanTimeInSeconds: Double?, completion: @escaping (Result<[YuchengDevice], any Error>) -> Void) {
       var isCompleted = false
       var lastConnectedDevice = YCProduct.shared.currentPeripheral;
       var ycDevices: [YuchengDevice] = [];
       do {
           YCProduct.scanningDevice(delayTime: scanTimeInSeconds ?? TIME_TO_SCAN) { devices, error in
               if (error != nil) {
                   self.onDevice(YuchengDeviceCompleteEvent(completed: false))
                   isCompleted = true;
                   completion(.success(ycDevices))
               } else {
                   self.scannedDevices = devices;
                   for device in devices {
                       var isCurrentDevice = lastConnectedDevice?.macAddress == device.macAddress;
                       self.currentDevice = isCurrentDevice ? device : nil;
                       let ycDevice = YuchengDevice(index: Int64(self.index), deviceName: device.name ?? "", uuid: device.macAddress, isCurrentConnected: isCurrentDevice)
                       self.onDevice(YuchengDeviceDataEvent(index: Int64(self.index), mac: device.macAddress, isCurrentConnected: isCurrentDevice, deviceName: device.name ?? device.deviceModel))
                       self.index += 1
                       ycDevices.append(ycDevice)
                       print("SCAN DEVICES : DEVICE = " + ycDevice.uuid + ", " + ycDevice.deviceName)
                   }
                   self.onDevice(YuchengDeviceCompleteEvent(completed: true))
                   completion(.success(ycDevices))
                   isCompleted = true
               }
           }
       } catch (let e) {
           self.onDevice(YuchengDeviceCompleteEvent(completed: false))
           completion(.failure(e))
       }
       DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT) {
           if (isCompleted) {
               return;
           }
           if (ycDevices.isEmpty) {
               self.onDevice(YuchengDeviceTimeOutEvent(isTimeout: true))
           } else {
               for ycDevice in ycDevices {
                   self.onDevice(YuchengDeviceDataEvent(index: Int64(self.index), mac: ycDevice.uuid, isCurrentConnected: ycDevice.isCurrentConnected, deviceName: ycDevice.deviceName))
                   self.index += 1
               }
               self.onDevice(YuchengDeviceTimeOutEvent(isTimeout: true))
           }
           completion(.success(ycDevices))
       }
   }
   
   func isDeviceConnected(device: YuchengDevice?, completion: @escaping (Result<Bool, any Error>) -> Void)
   {
       do {
           var lastConnectedDevice = YCProduct.shared.currentPeripheral;
           if (device == nil) {
               completion(.success(lastConnectedDevice != nil))
           }
           
           var isConnected = (lastConnectedDevice?.macAddress == device?.uuid);
           completion(.success(isConnected))
       } catch (let e) {
           completion(.failure(e))
       }
   }
   
   func connect(device: YuchengDevice, completion: @escaping (Result<Bool, any Error>) -> Void) {
       if (currentDevice != nil) {
           if (device.deviceName == currentDevice?.name || device.uuid == currentDevice?.macAddress) {
               completion(.success(true))
               return;
           }
       }
       
       currentDevice = scannedDevices.first(where: { scannedDevice in
           scannedDevice.name == device.deviceName || scannedDevice.macAddress == device.uuid
       })
       
       if (currentDevice == nil) {
           currentDevice = YCProduct.shared.currentPeripheral;
       }
       
       if (currentDevice == nil) {
           completion(.failure(NoDeviceError.noDevice("Current device is nil")))
       }
       
       var isCompleted = false;
       YCProduct.connectDevice(currentDevice!) { state, error in
           if let error = error {
               isCompleted = true
               completion(.failure(error));
           } else {
               if state == .connected {
                   completion(.success(true));
               } else {
                   completion(.success(false))
               }
               isCompleted = true
           }
       }
       DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT) {
           if (isCompleted) {
               return;
           }
           self.onState(YuchengDeviceStateTimeOutEvent(isTimeout: true))
           completion(.success(false))
       }
   }
   
   func reconnect(completion: @escaping (Result<Bool, any Error>) -> Void) {
       completion(.failure(UnimplementedError.notImplemented("Manual reconnect not support. SDK do it himself")))
   }
   
   func disconnect(completion: @escaping (Result<Void, any Error>) -> Void) {
       var isCompleted = false
       YCProduct.disconnectDevice(currentDevice ?? YCProduct.shared.currentPeripheral) { state, error in
           if let error = error {
               completion(.failure(error));
               isCompleted = true
           } else {
               completion(.success(()))
               isCompleted = true
           }
       }
       DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
           if (isCompleted) {
               return;
           }
           completion(.success(()))
       }
   }
   
   func getCurrentConnectedDevice(completion: @escaping (Result<YuchengDevice?, any Error>) -> Void) {
       do {
           currentDevice = YCProduct.shared.currentPeripheral
           var device = currentDevice
           if device == nil {
               completion(.success(nil))
               return
           }
           completion(.success(YuchengDevice(index: 0, deviceName: device!.name ?? device!.deviceModel, uuid: device!.macAddress, isCurrentConnected: true)))
       } catch (let e) {
           completion(.failure(e))
       }
   }
   
   private func querySleepData(_ completion: @escaping (Result<[(any YuchengSleepEvent)?], any Error>) -> Void, _ complete: @escaping () -> Void) {
       YCProduct.queryHealthData(dataType: YCQueryHealthDataType.sleep) { state, response in
           if state == .succeed, let datas = response as? [YCHealthDataSleep] {
               for info in datas {
                   let sleepData = self.converter.convert(sleepDataFromDevice: info)
                   self.onSleepData(sleepData)
                   self.sleepData.append(sleepData)
               }
               completion(.success(self.sleepData))
               self.sleepData = []
               complete()
           } else {
               completion(.success([]))
               print("No data")
               complete()
               self.sleepData = []
           }
       }
   }
   
   func getSleepData(completion: @escaping (Result<[(any YuchengSleepEvent)?], any Error>) -> Void) {
       do {
           var isCompleted = false
           querySleepData(completion, {
               isCompleted = true
           })
           DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT) {
               if (isCompleted) {
                   return
               }
               if (self.sleepData.isEmpty) {
                   self.onSleepData(YuchengSleepTimeOutEvent(isTimeout: true))
               } else {
                   for sleepData in self.sleepData {
                       self.onSleepData(sleepData)
                   }
               }
               completion(.success(self.sleepData))
           }
       } catch (let e) {
           completion(.failure(e))
       }
   }
}
