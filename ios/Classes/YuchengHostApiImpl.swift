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

final class YuchengHostApiImpl : YuchengHostApi {
    typealias DeviceHandler = (any YuchengDeviceEvent) -> Void
    typealias StateHandler = (any YuchengDeviceStateEvent) -> Void
    typealias SleepHandler = (any YuchengSleepEvent) -> Void
    typealias HealthHandler = (any YuchengHealthEvent) -> Void
    typealias SleepHealthHandler = (any YuchengSleepHealthEvent) -> Void
    private let onDevice: DeviceHandler;
    private let onSleepData: SleepHandler;
    private let onState: StateHandler;
    private let onHealth: HealthHandler;
    private let onSleepHealth: SleepHealthHandler;
    private let sleepConverter: YuchengSleepDataConverter;
    private let healdConverter: YuchengHealthDataConverter;
    private var scannedDevices: [CBPeripheral] = [];
    private var currentDevice: CBPeripheral? = nil;
    private var index: Int = 0;
    private let TIME_TO_TIMEOUT = 15.0;
    private let TIME_TO_TIMEOUT_RESET = 30.0;
    private let TIME_TO_SCAN = 15.0;
    private let TIME_TO_RECONNECT = 20;
    private let TIME_TO_QUERY_MAC_ADDR = 10;
    
    init(onDevice: @Sendable @escaping (_: YuchengDeviceEvent) -> Void, onSleepData: @Sendable @escaping (_: YuchengSleepEvent) -> Void, onState: @Sendable @escaping (_: YuchengDeviceStateEvent) -> Void, onHealth: @Sendable @escaping (_: YuchengHealthEvent) -> Void, onSleepHealth: @Sendable @escaping (_: YuchengSleepHealthEvent) -> Void, sleepConverter: YuchengSleepDataConverter, healthConverter:YuchengHealthDataConverter) {
        self.onDevice = onDevice
        self.onSleepData = onSleepData
        self.sleepConverter = sleepConverter
        self.healdConverter = healthConverter
        self.onState = onState
        self.onHealth = onHealth
        self.onSleepHealth = onSleepHealth
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: {
            let currentDevice = YCProduct.shared.currentPeripheral;
            if (currentDevice != nil) {
                onState(YuchengDeviceStateDataEvent(state: .readWriteOK))
            }
        })
    }
    
    func startScanDevices(scanTimeInSeconds: Double?, completion: @escaping (Result<[YuchengDevice], any Error>) -> Void) {
        var isCompleted = false
        let lastConnectedDevice = YCProduct.shared.currentPeripheral;
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
                        print("UUID DEVICE = " + device.identifier.uuidString)
                        let isReconnected = lastConnectedDevice?.macAddress == device.macAddress;
                        self.currentDevice = isReconnected ? device : nil;
                        if (!ycDevices.contains(where: { dev in
                            dev.uuid == device.macAddress
                        })) {
                            let ycDevice = YuchengDevice(index: Int64(self.index), deviceName: device.name ?? "", uuid: device.macAddress, isReconnected: isReconnected)
                            self.onDevice(YuchengDeviceDataEvent(index: Int64(self.index), mac: device.macAddress, isReconnected: ycDevice.isReconnected, deviceName: device.name ?? device.deviceModel))
                            self.index += 1
                            ycDevices.append(ycDevice)
                            print("SCAN DEVICES : DEVICE = " + ycDevice.uuid + ", " + ycDevice.deviceName)
                        }
                    }
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
                self.onDevice(YuchengDeviceCompleteEvent(completed: true))
            }
            completion(.success(ycDevices))
        }
    }
    
    func isDeviceConnected(device: YuchengDevice?, completion: @escaping (Result<Bool, any Error>) -> Void)
    {
        do {
            let lastConnectedDevice = YCProduct.shared.currentPeripheral;
            if (device == nil) {
                completion(.success(lastConnectedDevice != nil))
            }
            let isConnected = (lastConnectedDevice?.macAddress == device?.uuid);
            completion(.success(isConnected))
        } catch (let e) {
            completion(.failure(e))
        }
    }
    
    func connect(device: YuchengDevice, connectTimeInSeconds: Int64?, completion: @escaping (Result<Bool, any Error>) -> Void) {
        let timeout = Double(connectTimeInSeconds ?? Int64((TIME_TO_TIMEOUT + 10)))
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
            return
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
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            if (isCompleted) {
                return;
            }
            self.onState(YuchengDeviceStateTimeOutEvent(isTimeout: true))
            completion(.success(false))
        }
    }
    
    func reconnect(reconnectTimeInSeconds: Int64?, completion: @escaping (Result<Bool, any Error>) -> Void) {
        var isCompleted = false;
        do {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(TIME_TO_QUERY_MAC_ADDR)) {
                YCProduct.queryDeviceMacAddress { state, response in
                    if state == YCProductState.succeed,
                       let macAddress = response as? String {
                        self.currentDevice = YCProduct.shared.currentPeripheral
                        let device = self.currentDevice
                        let deviceMacAddress = device?.macAddress
                        let isReconnected = deviceMacAddress != nil
                        let isDevice = device != nil
                        if (isDevice) {
                            let ycDevice = YuchengDevice(index: Int64(self.index), deviceName: device?.name ?? "", uuid: deviceMacAddress ?? macAddress, isReconnected: isReconnected)
                            DispatchQueue.main.async {
                                self.onState(YuchengDeviceStateDataEvent(state: .readWriteOK))
                                self.onDevice(YuchengDeviceDataEvent(index: ycDevice.index, mac: ycDevice.uuid, isReconnected: ycDevice.isReconnected, deviceName: ycDevice.deviceName))
                            }
                        }
                        completion(.success(isDevice))
                        self.index += 1
                        isCompleted = true
                    }
                }
            }
        } catch {
            isCompleted = true
            completion(.failure(error))
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(TIME_TO_RECONNECT), execute: {
            if (isCompleted) {
                return
            }
            completion(.success(false))
        })
    }
    
    func disconnect(completion: @escaping (Result<Void, any Error>) -> Void) {
        var isCompleted = false
        YCProduct.disconnectDevice(currentDevice ?? YCProduct.shared.currentPeripheral) { state, error in
            if let error = error {
                completion(.failure(error));
                isCompleted = true
            } else {
                completion(.success(()))
                self.currentDevice = nil
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
            let device = currentDevice
            if device == nil {
                completion(.success(nil))
                return
            }
            completion(.success(YuchengDevice(index: 0, deviceName: device!.name ?? device!.deviceModel, uuid: device!.macAddress, isReconnected: true)))
        } catch (let e) {
            completion(.failure(e))
        }
    }
    
    func getDefaultStartAndEndDate() -> (start: Int64, end: Int64) {
        var startComponents = DateComponents()
        startComponents.weekOfYear = -1
        startComponents.day = -1
        var endComponents = DateComponents()
        endComponents.day = 1
        let date = Date().localDate()
        let currentDate = Calendar.current.startOfDay(for: date).localDate()
        let startDate = Calendar.current.date(byAdding: startComponents, to: currentDate)
        let endDate = Calendar.current.date(byAdding: endComponents, to: currentDate)
        let start = Int64(startDate?.timeIntervalSince1970 ?? 0).toMilliseconds()
        let end = Int64(endDate?.timeIntervalSince1970 ?? 0).toMilliseconds()
        return (start: start, end: end)
    }
    
    func getSleepData(startTimestamp: Int64?, endTimestamp: Int64?, completion: @escaping (Result<[(YuchengSleepData)], any Error>) -> Void) {
        let defaultDate = getDefaultStartAndEndDate()
        let start = startTimestamp ?? defaultDate.start
        let end = endTimestamp ?? defaultDate.end
        var isCompleted = false
        do {
            if (start >= end) {
                onSleepData(YuchengSleepErrorEvent(error: "Start timestamp cant be larger than end timestamp!"))
                completion(.success([]))
            }
            var sleepDataList: [YuchengSleepData] = []
            
            YCProduct.queryHealthData(dataType: YCQueryHealthDataType.sleep) { state, response in
                if state == .succeed, let datas = response as? [YCHealthDataSleep] {
                    for info in datas {
                        let sleepData = self.sleepConverter.convert(sleepDataFromDevice: info)
                        let isInRange = sleepData.startTimeStamp >= start && sleepData.endTimeStamp <= end
                        if (!isInRange) { continue }
                        sleepDataList.append(sleepData)
                        let ycSleepEvent = YuchengSleepDataEvent(sleepData: sleepData)
                        DispatchQueue.main.async {
                            self.onSleepData(ycSleepEvent)
                        }
                    }
                } else {
                    print("No data")
                }
                if (!isCompleted) {
                    DispatchQueue.main.async {
                        completion(.success(sleepDataList))
                    }
                }
                isCompleted = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT) {
                if (isCompleted) {
                    return;
                }
                for sleepData in sleepDataList {
                    let ycSleepEvent = YuchengSleepDataEvent(sleepData: sleepData)
                    DispatchQueue.main.async {
                        self.onSleepData(ycSleepEvent)
                    }
                }
                DispatchQueue.main.async {
                    self.onSleepData(YuchengSleepTimeOutEvent(isTimeout: true))
                }
            }
        } catch {
            isCompleted = true
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }
    
    
    func getHealthData(startTimestamp: Int64?, endTimestamp: Int64?, completion: @escaping (Result<[YuchengHealthData], any Error>) -> Void) {
        let defaultDate = getDefaultStartAndEndDate()
        let start = startTimestamp ?? defaultDate.start
        let end = endTimestamp ?? defaultDate.end
        var isCompleted = false
        do {
            if (start >= end) {
                onSleepData(YuchengSleepErrorEvent(error: "Start timestamp cant be larger than end timestamp!"))
                completion(.success([]))
            }
            
            var healthDataList: [YuchengHealthData] = []
            
            YCProduct.queryHealthData(dataType: YCQueryHealthDataType.combinedData) { state, response in
                if (isCompleted) {
                    return
                }
                
                if state == .succeed, let datas = response as? [YCHealthDataCombinedData] {
                    for info in datas {
                        let healthData = self.healdConverter.convert(healthDataFromDevice: info)
                        let isInRange = healthData.startTimestamp >= start && healthData.startTimestamp <= end
                        if (!isInRange) { continue }
                        healthDataList.append(healthData)
                        let ycHealthEvent = YuchengHealthDataEvent(healthData: healthData)
                        DispatchQueue.main.async {
                            self.onHealth(ycHealthEvent)
                        }
                    }
                } else {
                    print("No data")
                }
                if (!isCompleted) {
                    DispatchQueue.main.async {
                        completion(.success(healthDataList))
                    }
                }
                isCompleted = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT) {
                if (isCompleted) {
                    return;
                }
                for healthData in healthDataList {
                    let event = YuchengHealthDataEvent(healthData: healthData)
                    DispatchQueue.main.async { self.onHealth(event) }
                }
                DispatchQueue.main.async { self.onHealth(YuchengHealthTimeOutEvent(isTimeout: true)) }
            }
        } catch {
            isCompleted = true
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }
    
    func getSleepHealthData(startTimestamp: Int64?, endTimestamp: Int64?, completion: @escaping (Result<YuchengSleepHealthData, any Error>) -> Void) {
        let empty = YuchengSleepHealthData(sleepData: [], healthData: [])
        let defaultDate = getDefaultStartAndEndDate()
        let start = startTimestamp ?? defaultDate.start
        let end = endTimestamp ?? defaultDate.end
        var isHealthCompleted = false;
        var isSleepCompleted = false;
        var healthDataList: [YuchengHealthData] = []
        var sleepDataList: [YuchengSleepData] = []
        do {
            if (start >= end) {
                onSleepData(YuchengSleepErrorEvent(error: "Start timestamp cant be larger than end timestamp!"))
                completion(.success(empty))
            }
            do {
                YCProduct.queryHealthData(dataType: YCQueryHealthDataType.combinedData) { state, response in
                    if (isHealthCompleted) {
                        return
                    }
                    
                    if state == .succeed, let datas = response as? [YCHealthDataCombinedData] {
                        for info in datas {
                            let healthData = self.healdConverter.convert(healthDataFromDevice: info)
                            let isInRange = healthData.startTimestamp >= start && healthData.startTimestamp <= end
                            if (!isInRange) { continue }
                            healthDataList.append(healthData)
                            let ycHealthEvent = YuchengHealthDataEvent(healthData: healthData)
                            DispatchQueue.main.async {
                                self.onHealth(ycHealthEvent)
                            }
                        }
                    } else {
                        print("No data")
                    }
                    if (!isHealthCompleted && isSleepCompleted) {
                        DispatchQueue.main.async {
                            let data = YuchengSleepHealthData(sleepData: sleepDataList, healthData: healthDataList)
                            completion(.success(data))
                            self.onSleepHealth(YuchengSleepHealthDataEvent(data: data))
                        }
                    }
                    isHealthCompleted = true
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                isHealthCompleted = true
            }
            do {
                YCProduct.queryHealthData(dataType: YCQueryHealthDataType.sleep) { state, response in
                    if state == .succeed, let datas = response as? [YCHealthDataSleep] {
                        if (isSleepCompleted) {
                            return
                        }
                        for info in datas {
                            let sleepData = self.sleepConverter.convert(sleepDataFromDevice: info)
                            let isInRange = sleepData.startTimeStamp >= start && sleepData.endTimeStamp <= end
                            if (!isInRange) { continue }
                            sleepDataList.append(sleepData)
                            let ycSleepEvent = YuchengSleepDataEvent(sleepData: sleepData)
                            DispatchQueue.main.async {
                                self.onSleepData(ycSleepEvent)
                            }
                        }
                    } else {
                        print("No data")
                    }
                    if (!isSleepCompleted && isHealthCompleted) {
                        DispatchQueue.main.async {
                            let data = YuchengSleepHealthData(sleepData: sleepDataList, healthData: healthDataList)
                            completion(.success(data))
                            self.onSleepHealth(YuchengSleepHealthDataEvent(data: data))
                        }
                    }
                    isSleepCompleted = true
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                isSleepCompleted = true
            }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
            isHealthCompleted = true
            isSleepCompleted = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT, execute: {
            if (isHealthCompleted && isSleepCompleted) {
                return
            }
            DispatchQueue.main.async {
                self.onSleepHealth(YuchengSleepHealthDataEvent(data: empty))
                self.onSleepHealth(YuchengSleepHealthTimeOutEvent(isTimeout: true))
                completion(.success(empty))
            }
        })
    }
    
    func getDeviceSettings(completion: @escaping (Result<YuchengDeviceSettings?, any Error>) -> Void) {
        if (currentDevice == nil) {
            completion(.success(nil))
        }
        
        var isCompleted = false
        
        do {
            YCProduct.queryDeviceBasicInfo(completion: {state, response in
                if state == .succeed, let data = response as? YCDeviceBasicInfo {
                    let batteryValue = data.batteryPower
                    let settings = YuchengDeviceSettings(batteryValue: Int64(batteryValue))
                    if (isCompleted) {
                        return
                    }
                    isCompleted = true
                    DispatchQueue.main.async{
                        completion(.success(settings))
                    }
                }
            }
            )
        } catch {
            if (isCompleted) {
                return
            }
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT, execute: {
            if (isCompleted) {
                return
            }
            DispatchQueue.main.async {
                completion(.success(nil))
            }
        })
    }
    
    func deleteSleepData( completion: @escaping (Result<Bool, any Error>) -> Void) {
        var isCompleted = false
        do {
            let selectedDevice = self.currentDevice ?? YCProduct.shared.currentPeripheral
            YCProduct.deleteHealthData(selectedDevice, dataType: YCDeleteHealthDataType.sleep) { state, response in
                let isDeleted = state == YCProductState.succeed
                DispatchQueue.main.async {
                    completion(.success(isDeleted))
                }
            }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT, execute: {
            if (isCompleted) {
                return
            }
            DispatchQueue.main.async {
                completion(.success(false))
            }
        })
    }
    
    func deleteHealthData(completion: @escaping (Result<Bool, any Error>) -> Void) {
        var isCompleted = false
        do {
            let selectedDevice = self.currentDevice ?? YCProduct.shared.currentPeripheral
            YCProduct.deleteHealthData(selectedDevice, dataType: YCDeleteHealthDataType.combinedData) { state, response in
                let isDeleted = state == YCProductState.succeed
                DispatchQueue.main.async {
                    completion(.success(isDeleted))
                }
            }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT, execute: {
            if (isCompleted) {
                return
            }
            DispatchQueue.main.async {
                completion(.success(false))
            }
        })
    }
    
    func deleteSleepHealthData(completion: @escaping (Result<Bool, any Error>) -> Void) {
        var isHealthCompleted = false
        var isSleepCompleted = false
        do {
            let selectedDevice = self.currentDevice ?? YCProduct.shared.currentPeripheral
            YCProduct.deleteHealthData(selectedDevice, dataType: YCDeleteHealthDataType.sleep) { state, response in
                isSleepCompleted = state == YCProductState.succeed
                if (isSleepCompleted && isHealthCompleted) {
                    DispatchQueue.main.async {
                        completion(.success(isSleepCompleted && isHealthCompleted))
                    }
                }
            }
            YCProduct.deleteHealthData(selectedDevice, dataType: YCDeleteHealthDataType.combinedData) { state, response in
                isHealthCompleted = state == YCProductState.succeed
                if (isSleepCompleted && isHealthCompleted) {
                    DispatchQueue.main.async {
                        completion(.success(isSleepCompleted && isHealthCompleted))
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT, execute: {
            if (isHealthCompleted && isSleepCompleted) {
                return
            }
            DispatchQueue.main.async {
                completion(.success(false))
            }
        })
    }
    
    func resetToFactory(completion: @escaping (Result<Bool, any Error>) -> Void) {
        var isResetCompleted = false
        do {
            YCProduct.setDeviceReset { state, response in
                isResetCompleted = true
                DispatchQueue.main.async {
                    completion(Result.success(state == .succeed))
                }
            }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT_RESET, execute: {
            if (isResetCompleted) {
                return
            }
            DispatchQueue.main.async {
                completion(.success(false))
            }
        })
    }
}

extension Date {
    func localDate() -> Date {
        let timeZoneOffset = Double(TimeZone.current.secondsFromGMT(for: self))
        guard let localDate = Calendar.current.date(byAdding: .second, value: Int(timeZoneOffset), to: self) else {return self}
        
        return localDate
    }
}

extension Int64 {
    func toMilliseconds() -> Int64 {
        return self * 1000
    }
}
