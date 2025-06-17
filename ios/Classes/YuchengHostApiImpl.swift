//
//  YuchengHostApiImpl.swift
//  Pods
//
//  Created by Maxim Zarechnev on 10.04.2025.
//
import YCProductSDK
import CoreBluetooth
import Flutter

import Combine

final class Completer<T> : @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.crefter.yuchengble.yucheng_ble", attributes: .concurrent)
    private var continuation: CheckedContinuation<T, Error>?
    private var isResumed = false
    
    func complete(_ result: Result<T, Error>) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self, !self.isResumed else { return }
            switch result {
            case .success(let value):
                self.continuation?.resume(returning: value)
            case .failure(let error):
                self.continuation?.resume(throwing: error)
            }
            self.continuation = nil
            self.isResumed = true
        }
    }
    
    func awaitResult() async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async(flags: .barrier) { [weak self] in
                self?.continuation = continuation
            }
        }
    }
    
    func isCompleted() -> Bool {
        return queue.sync { self.isResumed }
    }
}


enum UnimplementedError : Error {
    case notImplemented(String)
}

enum NoDeviceError : Error {
    case noDevice(String)
}


final class YuchengHostApiImpl : YuchengHostApi, Sendable {
    typealias DeviceHandler = @Sendable (any YuchengDeviceEvent) -> Void
    typealias StateHandler = @Sendable (any YuchengDeviceStateEvent) -> Void
    typealias SleepHandler = @Sendable (any YuchengSleepEvent) -> Void
    typealias HealthHandler = @Sendable (any YuchengHealthEvent) -> Void
    typealias SleepHealthHandler = @Sendable (any YuchengSleepHealthEvent) -> Void
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
    private let TIME_TO_SCAN = 15.0;
    
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
        do {
            let a = YCProduct.shared.reconnectedDevice()
            currentDevice = YCProduct.shared.currentPeripheral
            let conn = YCProduct.shared.connectedPeripherals
            let isDevice = currentDevice != nil
            if (isDevice) {
                let ycDevice = YuchengDevice(index: Int64(index), deviceName: currentDevice?.name ?? "", uuid: currentDevice?.macAddress ?? "", isReconnected: true)
                DispatchQueue.main.async {
                    self.onDevice(YuchengDeviceDataEvent(index: ycDevice.index, mac: ycDevice.uuid, isReconnected: ycDevice.isReconnected, deviceName: ycDevice.deviceName))
                }
            }
            completion(.success(isDevice))
            index += 1
        } catch {
            completion(.failure(error))
        }
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
    
    private func getSleepData(skipHandler: Bool = false, startTimestamp: Int64, endTimestamp: Int64) async throws -> [YuchengSleepData] {
        if (startTimestamp >= endTimestamp) {
            onSleepData(YuchengSleepErrorEvent(error: "Start timestamp cant be larger than end timestamp!"))
            return []
        }
        let completer: Completer<[YuchengSleepData]> = Completer()
        var sleepDataList: [YuchengSleepData] = []
        let timeoutTask = DispatchWorkItem {
            guard !completer.isCompleted() else { return }
            if (!skipHandler) {
                for sleepData in sleepDataList {
                    let ycSleepEvent = YuchengSleepDataEvent(sleepData: sleepData)
                    DispatchQueue.main.async {
                        self.onSleepData(ycSleepEvent)
                    }
                }
            }
            completer.complete(.success(sleepDataList))
            DispatchQueue.main.async {
                self.onSleepData(YuchengSleepTimeOutEvent(isTimeout: true))
            }
        }
        
        YCProduct.queryHealthData(dataType: YCQueryHealthDataType.sleep) { state, response in
            if state == .succeed, let datas = response as? [YCHealthDataSleep] {
                for info in datas {
                    let sleepData = self.sleepConverter.convert(sleepDataFromDevice: info)
                    let isInRange = sleepData.startTimeStamp >= startTimestamp && sleepData.endTimeStamp <= endTimestamp
                    if (!isInRange) { continue }
                    sleepDataList.append(sleepData)
                    if (skipHandler) { continue }
                    let ycSleepEvent = YuchengSleepDataEvent(sleepData: sleepData)
                    DispatchQueue.main.async {
                        self.onSleepData(ycSleepEvent)
                    }
                }
            } else {
                print("No data")
            }
            if (!completer.isCompleted()) {
                completer.complete(.success(sleepDataList))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT, execute: timeoutTask)
        
        do {
            let data = try await completer.awaitResult()
            timeoutTask.cancel()
            return data
        } catch {
            throw error
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
        Task {
            let defaultDate = getDefaultStartAndEndDate()
            let start = startTimestamp ?? defaultDate.start
            let end = endTimestamp ?? defaultDate.end
            do {
                let sleepData = try await getSleepData(startTimestamp: start, endTimestamp: end)
                DispatchQueue.main.async {
                    completion(.success(sleepData))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    func getHealthData(skipHandler: Bool = false, startTimestamp: Int64, endTimestamp: Int64) async throws -> [YuchengHealthData] {
        if (startTimestamp >= endTimestamp) {
            onSleepData(YuchengSleepErrorEvent(error: "Start timestamp cant be larger than end timestamp!"))
            return []
        }
        
        let completer: Completer<[YuchengHealthData]> = Completer()
        var healthDataList: [YuchengHealthData] = []
        
        let timeoutTask = DispatchWorkItem {
            guard !completer.isCompleted() else { return }
            if (!skipHandler) {
                for healthData in healthDataList {
                    let event = YuchengHealthDataEvent(healthData: healthData)
                    DispatchQueue.main.async { self.onHealth(event) }
                }
            }
            completer.complete(.success(healthDataList))
            DispatchQueue.main.async { self.onHealth(YuchengHealthTimeOutEvent(isTimeout: true)) }
        }
        
        YCProduct.queryHealthData(dataType: YCQueryHealthDataType.combinedData) { state, response in
            guard !completer.isCompleted() else { return }
            
            if state == .succeed, let datas = response as? [YCHealthDataCombinedData] {
                for info in datas {
                    let healthData = self.healdConverter.convert(healthDataFromDevice: info)
                    let isInRange = healthData.startTimestamp >= startTimestamp && healthData.startTimestamp <= endTimestamp
                    if (!isInRange) { continue }
                    healthDataList.append(healthData)
                    if (skipHandler) { continue }
                    let ycHealthEvent = YuchengHealthDataEvent(healthData: healthData)
                    DispatchQueue.main.async {
                        self.onHealth(ycHealthEvent)
                    }
                }
            } else {
                print("No data")
            }
            if (!completer.isCompleted()) {
                completer.complete(.success(healthDataList))
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT, execute: timeoutTask)
        
        do {
            let data = try await completer.awaitResult()
            timeoutTask.cancel()
            return data
        } catch {
            throw error
        }
    }
    
    func getHealthData(startTimestamp: Int64?, endTimestamp: Int64?, completion: @escaping (Result<[YuchengHealthData], any Error>) -> Void) {
        Task {
            let defaultDate = getDefaultStartAndEndDate()
            let start = startTimestamp ?? defaultDate.start
            let end = endTimestamp ?? defaultDate.end
            do {
                let healthData = try await getHealthData(startTimestamp: start, endTimestamp: end)
                DispatchQueue.main.async {
                    completion(.success(healthData))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    func getSleepHealthData(startTimestamp: Int64?, endTimestamp: Int64?, completion: @escaping (Result<YuchengSleepHealthData, any Error>) -> Void) {
        let completer: Completer<YuchengSleepHealthData> = Completer()
        let empty = YuchengSleepHealthData(sleepData: [], healthData: [])
        let timeoutTask = DispatchWorkItem {
            guard !completer.isCompleted() else { return }
            DispatchQueue.main.async {
                self.onSleepHealth(YuchengSleepHealthDataEvent(data: empty))
                completer.complete(.success(empty))
                self.onSleepHealth(YuchengSleepHealthTimeOutEvent(isTimeout: true))
            }
        }
        Task {
            let defaultDate = getDefaultStartAndEndDate()
            let start = startTimestamp ?? defaultDate.start
            let end = endTimestamp ?? defaultDate.end
            do {
                let healthData = try await getHealthData(skipHandler: true, startTimestamp: start, endTimestamp: end)
                let sleepData = try await getSleepData(skipHandler: true, startTimestamp: start, endTimestamp: end)
                let ycData = YuchengSleepHealthData(sleepData: sleepData, healthData: healthData)
                DispatchQueue.main.async {
                    self.onSleepHealth(YuchengSleepHealthDataEvent(data: ycData))
                    if (!completer.isCompleted()) {
                        completer.complete(.success(ycData))
                    }
                }
            } catch {
                if (!completer.isCompleted()) {
                    completer.complete(.failure(error))
                }
            }
        }
        Task {
            do {
                let ycSleepHealth = try await completer.awaitResult()
                DispatchQueue.main.async {
                    completion(.success(ycSleepHealth))
                }
                timeoutTask.cancel()
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                timeoutTask.cancel()
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT, execute: timeoutTask)
    }
    
    func getDeviceSettings(completion: @escaping (Result<YuchengDeviceSettings?, any Error>) -> Void) {
        let completer: Completer<YuchengDeviceSettings?> = Completer();
        
        if (currentDevice == nil) {
            completer.complete(Result.success(nil))
        }
        let timeoutTask = DispatchWorkItem {
            guard !completer.isCompleted() else { return }
            DispatchQueue.main.async {
                completer.complete(.success(nil))
            }
        }
        
        do {
            YCProduct.queryDeviceBasicInfo(completion: {state, response in
                if state == .succeed, let data = response as? YCDeviceBasicInfo {
                    let batteryValue = data.batteryPower
                    let settings = YuchengDeviceSettings(batteryValue: Int64(batteryValue))
                    if (!completer.isCompleted()) {
                        completer.complete(.success(settings))
                    }
                }
            })
        } catch {
            if (!completer.isCompleted()) {
                completer.complete(.failure(error))
            }
        }
        
        Task {
            do {
                let settings = try await completer.awaitResult()
                DispatchQueue.main.async {
                    completion(.success(settings))
                }
                timeoutTask.cancel()
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                timeoutTask.cancel()
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT, execute: timeoutTask)
    }
    
    func deleteData(dataType: YCDeleteHealthDataType) async throws -> Bool {
        let completer = Completer<Bool>()
        
        let timeoutTask = DispatchWorkItem {
            guard !completer.isCompleted() else { return }
            DispatchQueue.main.async {
                completer.complete(.success(false))
            }
        }
        
        Task {
            do {
                let selectedDevice = self.currentDevice ?? YCProduct.shared.currentPeripheral
                YCProduct.deleteHealthData(selectedDevice, dataType: dataType) { state, response in
                    let isDeleted = state == YCProductState.succeed
                    DispatchQueue.main.async {
                        completer.complete(Result.success(isDeleted))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completer.complete(.failure(error))
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT, execute: timeoutTask)
        
        do {
            let result = try await completer.awaitResult()
            timeoutTask.cancel()
            return result
        } catch {
            timeoutTask.cancel()
            throw error
        }
    }
    
    func deleteSleepData( completion: @escaping (Result<Bool, any Error>) -> Void) {
        Task {
            do {
                let isDeleted = try await deleteData(dataType: YCDeleteHealthDataType.sleep)
                DispatchQueue.main.async {
                    completion(.success(isDeleted))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    func deleteHealthData(completion: @escaping (Result<Bool, any Error>) -> Void) {
        Task {
            do {
                let isDeleted = try await deleteData(dataType: YCDeleteHealthDataType.combinedData)
                DispatchQueue.main.async {
                    completion(.success(isDeleted))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    func deleteSleepHealthData(completion: @escaping (Result<Bool, any Error>) -> Void) {
        Task {
            do {
                let isSleepDeleted = try await deleteData(dataType: YCDeleteHealthDataType.sleep)
                let isHealthDeleted = try await deleteData(dataType: YCDeleteHealthDataType.combinedData)
                let isDeleted = isSleepDeleted && isHealthDeleted
                DispatchQueue.main.async {
                    completion(.success(isDeleted))
                    if (isDeleted) {
                        self.onSleepHealth(YuchengSleepHealthDataEvent(data: YuchengSleepHealthData(sleepData: [], healthData: [])))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
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
