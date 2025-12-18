//
//  YuchengHostApiImpl.swift
//  Pods
//
//  Created by Maxim Zarechnev on 10.04.2025.
//
import YCProductSDK
import CoreBluetooth
import Flutter
import JLDialUnit
import JL_BLEKit

import Combine

class Completer<T> {
    private let subject = PassthroughSubject<T, Error>()
    private let lock = NSRecursiveLock()
    private var _isCompleted = false
    
    /// Public future that can be subscribed to
    public var future: AnyPublisher<T, Error> {
        subject.eraseToAnyPublisher()
    }
    
    /// Thread-safe completion status
    public var isCompleted: Bool {
        lock.withLock { _isCompleted }
    }
    
    /// Completes the future with a value
    /// - Parameter value: The value to complete with
    public func complete(_ value: T) {
        guard !markAsCompleted() else { return }
        
        subject.send(value)
        subject.send(completion: .finished)
    }
    
    /// Completes the future with an error
    /// - Parameter error: The error to complete with
    public func completeError(_ error: Error) {
        guard !markAsCompleted() else { return }
        
        subject.send(completion: .failure(error))
    }
    
    /// Resets the completer to allow reuse (use with caution)
    public func reset() {
        lock.withLock {
            _isCompleted = false
        }
    }
    
    // MARK: - Private
    private func markAsCompleted() -> Bool {
        lock.withLock {
            guard !_isCompleted else {
                debugPrint("⚠️ Completer already completed")
                return true
            }
            _isCompleted = true
            return false
        }
    }
    
    deinit {
        // Ensure we complete the subject on deinit to avoid memory leaks
        if !isCompleted {
            subject.send(completion: .finished)
        }
    }
}

enum UnimplementedError : Error {
    case notImplemented(String)
}

enum NoDeviceError : Error {
    case noDevice(String)
}

enum UpgradeFirmwareError: Error {
    case failed(String)
    case unknown(String)
}

class UserExitedMeasurementException: Error {}
class RealTimeMeasurementFailedException: Error {}
class NoConnectionException : Error {}

final class YuchengHostApiImpl : YuchengHostApi {
    typealias DeviceHandler = (any YuchengDeviceEvent) -> Void
    typealias StateHandler = (any YuchengDeviceStateEvent) -> Void
    typealias SleepHandler = (any YuchengSleepEvent) -> Void
    typealias HealthHandler = (any YuchengHealthEvent) -> Void
    typealias AllDataHandler = (any YuchengAllEvent) -> Void
    typealias UpdateHandler = (any YuchengUpdateEvent) -> Void
    typealias AssetPathHandler = (String) -> String;
    
    public var bloodOxygens: [Int64] = [];
    public var sbps: [Int64] = [];
    public var dbps: [Int64] = [];
    public var heartRates: [Int64] = [];
    public var steps: Int64 = 0;
    public var distance: Int64 = 0;
    public var calories: Int64 = 0;
    public var bloodPressureCompleter: Completer<Bool>? = nil;
    public var bloodOxygenCompleter: Completer<Bool>? = nil;
    
    private var bloodPressureCancellables = Set<AnyCancellable>()
    private var oxygenCancellables = Set<AnyCancellable>()
    private var ringState: YuchengDeviceState = YuchengDeviceState.unknown;
    private let onDevice: DeviceHandler;
    private let onSleepData: SleepHandler;
    private let onState: StateHandler;
    private let onUpdate: UpdateHandler;
    private let onHealth: HealthHandler;
    private let onAllData: AllDataHandler;
    private let sleepConverter: YuchengSleepDataConverter;
    private let healthConverter: YuchengHealthDataConverter;
    private let sportConverter: YuchengSportDataConverter;
    private let assetPathHandler: AssetPathHandler;
    private var scannedDevices: [CBPeripheral] = [];
    private var scannedDevicesToUpdate: [CBPeripheral] = [];
    private var currentDevice: CBPeripheral? = nil;
    private var index: Int = 0;
    private let TIME_TO_TIMEOUT = 15.0;
    private let TIME_TO_TIMEOUT_RESET = 30.0;
    private let TIME_TO_SCAN = 15.0;
    private let TIME_TO_SCAN_TIMEOUT = 20.0;
    private let TIME_TO_RECONNECT = 20;
    private let TIME_TO_QUERY_MAC_ADDR = 10;
    /// Limit on number of repeated scans
    private let REPEAT_SCAN_JL_FORCE_OTA_COUNT = 10
    private let REALTIME_TIMEOUT = 90;
    /// Number of repeated scans
    private var repeatScanJLCount: Int = 0
    /// Connect back to device address
    private var reconnectMacAddress: String = ""
    private var filePathToUpdate: String = ""
    private var isUpgradeCompleted = false
    private var isUiUpgradeCompleted = false
    
    init(onDevice: @Sendable @escaping (_: YuchengDeviceEvent) -> Void, onSleepData: @Sendable @escaping (_: YuchengSleepEvent) -> Void, onState: @Sendable @escaping (_: YuchengDeviceStateEvent) -> Void, onHealth: @Sendable @escaping (_: YuchengHealthEvent) -> Void, onAllData: @Sendable @escaping (_: YuchengAllEvent) -> Void, sleepConverter: YuchengSleepDataConverter, healthConverter:YuchengHealthDataConverter, sportConverter: YuchengSportDataConverter, assetPathHandler: @Sendable @escaping (_: String) -> String, onUpdate: @Sendable @escaping  (_: YuchengUpdateEvent) -> Void) {
        self.onDevice = onDevice
        self.onSleepData = onSleepData
        self.sleepConverter = sleepConverter
        self.healthConverter = healthConverter
        self.sportConverter = sportConverter
        self.onState = onState
        self.onHealth = onHealth
        self.onAllData = onAllData
        self.assetPathHandler = assetPathHandler
        self.onUpdate = onUpdate
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: {
            let currentDevice = YCProduct.shared.currentPeripheral;
            if (currentDevice != nil) {
                onState(YuchengDeviceStateDataEvent(state: .readWriteOK))
            }
        })
        
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
    
    deinit {
        NotificationCenter.default.removeObserver(
            self,
            name: YCProduct.deviceStateNotification,
            object: nil
        )
        
        NotificationCenter.default.removeObserver(
            self,
            name: YCProduct.receivedRealTimeNotification,
            object: nil
        )
        
        NotificationCenter.default.removeObserver(
            self,
            name: YCProduct.deviceControlNotification,
            object: nil
        )
    }
    
    @objc func deviceDataStateChanged(_ ntf: Notification) {
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
                if (state == YCAppControlMeasureHealthDataResult.exit) {
                    print("BLOOD PRESSURE/HEART EXIT")
                    self.bloodPressureCompleter?.completeError(UserExitedMeasurementException())
                } else if (state == YCAppControlMeasureHealthDataResult.fail) {
                    print("BLOOD PRESSURE/HEART FAILED")
                    self.bloodPressureCompleter?.completeError(RealTimeMeasurementFailedException())
                } else {
                    print("BLOOD PRESSURE/HEART COMPLETE")
                    self.bloodPressureCompleter?.complete(true)
                }
            } else if (type == YCAppControlMeasureHealthDataType.bloodOxygen) {
                if (state == YCAppControlMeasureHealthDataResult.exit) {
                    print("BLOOD OXYGEN EXIT")
                    self.bloodOxygenCompleter?.completeError(UserExitedMeasurementException())
                } else if (state == YCAppControlMeasureHealthDataResult.fail) {
                    print("BLOOD OXYGEN FAILED")
                    self.bloodPressureCompleter?.completeError(RealTimeMeasurementFailedException())
                } else {
                    print("BLOOD OXYGEN COMPLETE")
                    self.bloodOxygenCompleter?.complete(true)
                }

            }
            let description = data.description
            print("CONTROL DATA RESULT",device.name ?? "",
                  state,
                  type,
                  description
            )
        }
    }
    
    @objc func deviceStateChange(_ ntf: Notification) {
        guard let info = ntf.userInfo as? [String: Any],
              let state = info[YCProduct.connecteStateKey] as? YCProductState else {
            return
        }
        if (state == YCProductState.connected) {
            self.ringState = YuchengDeviceState.connected
            self.onState(YuchengDeviceStateDataEvent(state: YuchengDeviceState.connected))
        } else if (state == YCProductState.connectedFailed) {
            self.ringState = YuchengDeviceState.connectedFailed
            self.onState(YuchengDeviceStateDataEvent(state: YuchengDeviceState.connectedFailed))
        } else if (state == YCProductState.disconnected) {
            self.ringState = YuchengDeviceState.disconnected
            self.onState(YuchengDeviceStateDataEvent(state: YuchengDeviceState.disconnected))
        } else if (state == YCProductState.unavailable) {
            self.ringState = YuchengDeviceState.unavailable
            self.onState(YuchengDeviceStateDataEvent(state: YuchengDeviceState.unavailable))
        } else if (state == YCProductState.timeout) {
            self.ringState = YuchengDeviceState.timeOut
            self.onState(YuchengDeviceStateDataEvent(state: YuchengDeviceState.timeOut))
        } else if (state == YCProductState.succeed) {
            self.ringState = YuchengDeviceState.readWriteOK
            self.onState(YuchengDeviceStateDataEvent(state: YuchengDeviceState.readWriteOK))
        } else {
            self.ringState = YuchengDeviceState.unknown
            self.onState(YuchengDeviceStateDataEvent(state: YuchengDeviceState.unknown))
        }
        print("STATE: " + state.toString)
    }
    
    @objc func receiveRealTimeData(_ notification: Notification) {
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
            self.setSteps(steps: Int64(sportInfo.step))
            self.setCalories(calories: Int64(sportInfo.calories))
            self.setDistance(distance: Int64(sportInfo.distance))
        }
        if let response =
            info[YCReceivedRealTimeDataType.realTimeMonitoringMode.toString] as?
            YCReceivedDeviceReportInfo {
           let device = response.device
            print("REAL TIME MONITORING MODE", response.data ?? "")
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
                self.heartRates.append(Int64(heartRate))
                self.dbps.append(Int64(diastolicBloodPressure))
                self.sbps.append(Int64(systolicBloodPressure))
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
                self.bloodOxygens.append(bloodOxygen)
                print("BLOOD OXYGEN INT", device?.name ?? "",
                      response.data ?? "no blood oxygen data"
                )
            }
        }
    }
    
    func addBlooxOxygen(item: Int64) {
        bloodOxygens.append(item)
    }
    
    func addSbp(item: Int64) {
        sbps.append(item)
    }
    
    func addDbp(item: Int64) {
        dbps.append(item)
    }
    
    func addHeartRate(item: Int64) {
        heartRates.append(item)
    }
    
    func setSteps(steps: Int64) {
        self.steps = steps
    }
    
    func setCalories(calories: Int64) {
        self.calories = calories
    }
    
    func setDistance(distance: Int64) {
        self.distance = distance
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
                        DispatchQueue.main.async {
                            print("UUID DEVICE = " + device.identifier.uuidString)
                            let deviceMac = device.macAddress
                            let deviceName = device.name
                            let isReconnected = lastConnectedDevice?.macAddress == deviceMac;
                            self.currentDevice = isReconnected ? device : nil;
                            if (!ycDevices.contains(where: { dev in
                                dev.uuid == deviceMac || dev.deviceName == deviceName
                            })) {
                                let ycDevice = YuchengDevice(index: Int64(self.index), deviceName: device.name ?? "", uuid: device.macAddress, isReconnected: isReconnected)
                                self.onDevice(YuchengDeviceDataEvent(index: Int64(self.index), mac: deviceMac, isReconnected: ycDevice.isReconnected, deviceName: deviceName ?? device.deviceModel))
                                self.index += 1
                                ycDevices.append(ycDevice)
                                print("SCAN DEVICES : DEVICE = " + ycDevice.uuid + ", " + ycDevice.deviceName)
                            }
                        }
                    }
                }
            }
        } catch (let e) {
            self.onDevice(YuchengDeviceCompleteEvent(completed: false))
            completion(.failure(e))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_SCAN_TIMEOUT) {
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
            if self.ringState == YuchengDeviceState.connected || self.ringState == YuchengDeviceState.readWriteOK {
                completion(.success(true))
                return
            }
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
        let timeout = connectTimeInSeconds ?? Int64((TIME_TO_TIMEOUT + 10))
        if (currentDevice != nil) {
            if (device.deviceName == currentDevice?.name || device.uuid == currentDevice?.macAddress) {
                completion(.success(true))
                return;
            }
        }
        
        currentDevice = scannedDevices.first(where: { scannedDevice in
            scannedDevice.name == device.deviceName
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
                    let device = YCProduct.shared.currentPeripheral;
                    let mac = device?.macAddress ?? "";
                    let name = device?.name ?? "";
                    isCompleted = true
                    completion(.success(true));
                    if (device != nil) {
                        self.currentDevice = device
                        let isOtaForce = YCProduct.isJLDeviceForceOTA()
                        if (isOtaForce) {
                            self.reconnectMacAddress = mac
                            self.connectForceOtaDevice { res in }
                        }
                        DispatchQueue.main.async(execute:  {
                            self.onDevice(YuchengDeviceDataEvent(index: Int64(self.index), mac: mac, isReconnected: false, deviceName: name))
                        })
                    }
                } else {
                    if (!isCompleted) {
                        isCompleted = true
                        completion(.success(false))
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(Int(timeout))) {
            if (isCompleted) {
                return;
            }
            self.onState(YuchengDeviceStateTimeOutEvent(isTimeout: true))
            completion(.success(false))
            isCompleted = true
        }
    }
    
    func reconnect(uuid: String?, reconnectTimeInSeconds: Int64?, completion: @escaping (Result<Bool, any Error>) -> Void) {
        var isCompleted = false;
        do {
            let isOtaForce = YCProduct.isJLDeviceForceOTA()
            if (isOtaForce) {
                self.currentDevice = YCProduct.shared.currentPeripheral
                self.reconnectMacAddress = self.currentDevice?.macAddress ?? uuid ?? ""
                self.connectForceOtaDevice { res in }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(TIME_TO_QUERY_MAC_ADDR)) {
                YCProduct.queryDeviceMacAddress { state, response in
                    self.currentDevice = YCProduct.shared.currentPeripheral
                    if state == YCProductState.succeed,
                       let macAddress = response as? String {
                        print("Reconnect: state == success")
                        self.currentDevice = YCProduct.shared.currentPeripheral
                        let device = self.currentDevice
                        let deviceMacAddress = device?.macAddress
                        let isReconnected = deviceMacAddress != nil
                        let isDevice = device != nil
                        if (isDevice) {
                            print("Reconnect: state == success, isDevice = true")
                            let ycDevice = YuchengDevice(index: Int64(self.index), deviceName: device?.name ?? "", uuid: deviceMacAddress ?? macAddress, isReconnected: isReconnected)
                            DispatchQueue.main.async {
                                self.onState(YuchengDeviceStateDataEvent(state: .readWriteOK))
                                self.onDevice(YuchengDeviceDataEvent(index: ycDevice.index, mac: ycDevice.uuid, isReconnected: ycDevice.isReconnected, deviceName: ycDevice.deviceName))
                            }
                            completion(.success(isDevice))
                            self.index += 1
                            isCompleted = true
                        } else {
                            print("Reconnect: state == success, isDevice = false, try forward connect")
                            YCProduct.connectDevice(self.currentDevice!) { state, error in
                                if let error = error {
                                    print("Reconnect: state == success, forward connect with error")
                                    isCompleted = true
                                    completion(.failure(error));
                                } else {
                                    if state == .connected {
                                        print("Reconnect: state == success, connected!")
                                        let device = YCProduct.shared.currentPeripheral;
                                        let mac = device?.macAddress ?? "";
                                        let name = device?.name ?? "";
                                        isCompleted = true
                                        completion(.success(true));
                                        if (device != nil) {
                                            self.currentDevice = device
                                            let isOtaForce = YCProduct.isJLDeviceForceOTA()
                                            if (isOtaForce) {
                                                self.reconnectMacAddress = mac
                                                self.connectForceOtaDevice { res in }
                                            }
                                            DispatchQueue.main.async(execute:  {
                                                self.onState(YuchengDeviceStateDataEvent(state: .readWriteOK))
                                                self.onDevice(YuchengDeviceDataEvent(index: Int64(self.index), mac: mac, isReconnected: true, deviceName: name))
                                            })
                                            self.index += 1
                                        }
                                    } else {
                                        print("Reconnect: state == success, cant connect")
                                        if (!isCompleted) {
                                            isCompleted = true
                                            completion(.success(false))
                                        }
                                    }
                                }
                                self.index += 1
                                isCompleted = true
                            }
                        }
                    } else {
                        print("Reconnect: state != success")
                        if self.currentDevice == nil {
                            print("Reconnect: state != success, currentDevice == nil")
                            completion(.success(false))
                            isCompleted = true
                            return
                        }
                        print("Reconnect: state != success, try forward connect")
                        YCProduct.connectDevice(self.currentDevice!) { state, error in
                            if let error = error {
                                print("Reconnect: state != success, try forward connect, done = error")
                                isCompleted = true
                                completion(.failure(error));
                            } else {
                                if state == .connected {
                                    print("Reconnect: state != success, try forward connect, connected!")
                                    let device = YCProduct.shared.currentPeripheral;
                                    let mac = device?.macAddress ?? "";
                                    let name = device?.name ?? "";
                                    isCompleted = true
                                    completion(.success(true));
                                    if (device != nil) {
                                        self.currentDevice = device
                                        let isOtaForce = YCProduct.isJLDeviceForceOTA()
                                        if (isOtaForce) {
                                            self.reconnectMacAddress = mac
                                            self.connectForceOtaDevice { res in }
                                        }
                                        DispatchQueue.main.async(execute:  {
                                            self.onState(YuchengDeviceStateDataEvent(state: .readWriteOK))
                                            self.onDevice(YuchengDeviceDataEvent(index: Int64(self.index), mac: mac, isReconnected: true, deviceName: name))
                                        })
                                        self.index += 1
                                    }
                                } else {
                                    print("Reconnect: state != success, try forward connect, NOT connected!")
                                    if (!isCompleted) {
                                        isCompleted = true
                                        completion(.success(false))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            isCompleted = true
            completion(.failure(error))
        }
        let seconds = reconnectTimeInSeconds == nil ? DispatchTimeInterval.seconds(TIME_TO_RECONNECT) : DispatchTimeInterval.seconds(Int(reconnectTimeInSeconds!))
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: {
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
                isCompleted = true
            }
            self.currentDevice = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if (isCompleted) {
                return;
            }
            completion(.success(()))
        }
    }
    
    func getCurrentConnectedDevice(completion: @escaping (Result<YuchengDevice?, any Error>) -> Void) {
        let timeoutForGetDevice = 5.0
        let timeout = timeoutForGetDevice * 2
        
        if (currentDevice != nil) {
            completion(.success(YuchengDevice(index: 0, deviceName: currentDevice!.name ?? currentDevice!.deviceModel, uuid: currentDevice!.macAddress, isReconnected: true)))
            return
        }
        
        var isCompleted = false
        do {
            DispatchQueue.main.asyncAfter(deadline: .now() + timeoutForGetDevice) {
                self.currentDevice = YCProduct.shared.currentPeripheral
                let device = self.currentDevice
                if device == nil {
                    completion(.success(nil))
                    return
                }
                completion(.success(YuchengDevice(index: Int64(self.index), deviceName: device!.name ?? device!.deviceModel, uuid: device!.macAddress, isReconnected: true)))
                self.index += 1
                isCompleted = true
            }
        } catch (let e) {
            DispatchQueue.main.async {
                completion(.failure(e))
            }
            isCompleted = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            if (isCompleted) {
                return
            }
            completion(.success(nil))
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
        if ringState != YuchengDeviceState.connected && ringState != YuchengDeviceState.readWriteOK {
            completion(.failure(NoConnectionException()))
            return
        }
        let start = startTimestamp ?? defaultDate.start
        let end = endTimestamp ?? defaultDate.end
        var isCompleted = false
        do {
            if (start >= end) {
                onSleepData(YuchengSleepErrorEvent(error: "Start timestamp cant be larger than end timestamp!"))
                completion(.success([]))
            }
            var sleepDataList: [YuchengSleepData] = []
            let device = YCProduct.shared.currentPeripheral;
            let _ = device?.macAddress
            let _ = device?.name
            
            YCProduct.queryHealthData(device, dataType: YCQueryHealthDataType.sleep) { state, response in
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
    
    
    func getHealthSportData(startTimestamp: Int64?, endTimestamp: Int64?, completion: @escaping (Result<YuchengHealthSportData, any Error>) -> Void) {
        let defaultDate = getDefaultStartAndEndDate()
        if ringState != YuchengDeviceState.connected && ringState != YuchengDeviceState.readWriteOK {
            completion(.failure(NoConnectionException()))
            return
        }
        let start = startTimestamp ?? defaultDate.start
        let end = endTimestamp ?? defaultDate.end
        var isHealthCompleted = false
        var isSportCompleted = false
        do {
            if (start >= end) {
                onSleepData(YuchengSleepErrorEvent(error: "Start timestamp cant be larger than end timestamp!"))
                completion(.success(YuchengHealthSportData(healthData: [], sportData: [])))
            }
            
            var healthDataList: [YuchengHealthData] = []
            var sportDataList: [YuchengSportData] = []
            let device = self.currentDevice ?? YCProduct.shared.currentPeripheral;
            let _ = device?.macAddress
            let _ = device?.name
            
            YCProduct.queryHealthData(device, dataType: YCQueryHealthDataType.step) { state, response in
                if state == .succeed, let datas = response as? [YCHealthDataStep] {
                    for info in datas {
                        let sportData = self.sportConverter.convert(sportDataFromDevice: info)
                        let isInRange = sportData.startTimeStamp >= start && sportData.endTimeStamp <= end
                        if (!isInRange) { continue }
                        sportDataList.append(sportData)
                    }
                }
                else {
                    print("No sport data")
                }
                if (isHealthCompleted && !isSportCompleted) {
                    DispatchQueue.main.async {
                        let healthSportData = YuchengHealthSportData(healthData: healthDataList, sportData: sportDataList)
                        completion(.success(healthSportData))
                        self.onHealth(YuchengHealthDataEvent(healthData: healthSportData))
                    }
                }
                
                isSportCompleted = true
            }
            
            YCProduct.queryHealthData(device, dataType: YCQueryHealthDataType.combinedData) { state, response in                
                if state == .succeed, let datas = response as? [YCHealthDataCombinedData] {
                    for info in datas {
                        let healthData = self.healthConverter.convert(healthDataFromDevice: info)
                        let isInRange = healthData.startTimestamp >= start && healthData.startTimestamp <= end
                        if (!isInRange) { continue }
                        healthDataList.append(healthData)
                    }
                } else {
                    print("No data")
                }
                if (isSportCompleted && !isHealthCompleted) {
                    DispatchQueue.main.async {
                        let healthSportData = YuchengHealthSportData(healthData: healthDataList, sportData: sportDataList)
                        completion(.success(healthSportData))
                        self.onHealth(YuchengHealthDataEvent(healthData: healthSportData))
                    }
                }
                isHealthCompleted = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT) {
                if (isHealthCompleted || isSportCompleted) {
                    return;
                }
                DispatchQueue.main.async {
                    self.onHealth(YuchengHealthDataEvent(healthData: YuchengHealthSportData(healthData: healthDataList, sportData: sportDataList)))
                }
                DispatchQueue.main.async { self.onHealth(YuchengHealthTimeOutEvent(isTimeout: true)) }
            }
        } catch {
            isHealthCompleted = true
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }
    
    func getAllData(startTimestamp: Int64?, endTimestamp: Int64?, completion: @escaping (Result<YuchengAllData, any Error>) -> Void) {
        if ringState != YuchengDeviceState.connected && ringState != YuchengDeviceState.readWriteOK {
            completion(.failure(NoConnectionException()))
            return
        }
        let empty = YuchengAllData(sleepData: [], healthSportData: YuchengHealthSportData(healthData: [], sportData: []))
        let defaultDate = getDefaultStartAndEndDate()
        let start = startTimestamp ?? defaultDate.start
        let end = endTimestamp ?? defaultDate.end
        var isHealthCompleted = false;
        var isSleepCompleted = false;
        var isSportCompleted = false;
        var healthDataList: [YuchengHealthData] = []
        var sleepDataList: [YuchengSleepData] = []
        var sportDataList: [YuchengSportData] = []
        let device = self.currentDevice ?? YCProduct.shared.currentPeripheral;
        let _ = device?.macAddress
        let _ = device?.name
        do {
            if (start >= end) {
                onSleepData(YuchengSleepErrorEvent(error: "Start timestamp cant be larger than end timestamp!"))
                completion(.success(empty))
            }
            do {
                YCProduct.queryHealthData(device, dataType: YCQueryHealthDataType.step) { state, response in
                    if state == .succeed, let datas = response as? [YCHealthDataStep] {
                        for info in datas {
                            let sportData = self.sportConverter.convert(sportDataFromDevice: info)
                            let isInRange = sportData.startTimeStamp >= start && sportData.endTimeStamp <= end
                            if (!isInRange) { continue }
                            sportDataList.append(sportData)
                        }
                    }
                    else {
                        print("No sport data")
                    }
                    
                    if (isHealthCompleted && isSleepCompleted && !isSportCompleted) {
                        DispatchQueue.main.async {
                            let healthSportData = YuchengHealthSportData(healthData: healthDataList, sportData: sportDataList)
                            let data = YuchengAllData(sleepData: sleepDataList, healthSportData: healthSportData)
                            completion(.success(data))
                            self.onAllData(YuchengAllDataEvent(data: data))
                        }
                    }
                    
                    isSportCompleted = true
                }
                
                YCProduct.queryHealthData(device, dataType: YCQueryHealthDataType.combinedData) { state, response in
                    if (isHealthCompleted) {
                        return
                    }
                    
                    if state == .succeed, let datas = response as? [YCHealthDataCombinedData] {
                        for info in datas {
                            let healthData = self.healthConverter.convert(healthDataFromDevice: info)
                            let isInRange = healthData.startTimestamp >= start && healthData.startTimestamp <= end
                            if (!isInRange) { continue }
                            healthDataList.append(healthData)
                        }
                    } else {
                        print("No data")
                    }
                    if (!isHealthCompleted && isSleepCompleted && isSportCompleted) {
                        DispatchQueue.main.async {
                            let healthSportData = YuchengHealthSportData(healthData: healthDataList, sportData: sportDataList)
                            let data = YuchengAllData(sleepData: sleepDataList, healthSportData: healthSportData)
                            completion(.success(data))
                            self.onAllData(YuchengAllDataEvent(data: data))
                        }
                    }
                    isHealthCompleted = true
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                isHealthCompleted = true
                isSportCompleted = true
            }
            do {
                YCProduct.queryHealthData(device, dataType: YCQueryHealthDataType.sleep) { state, response in
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
                    if (!isSleepCompleted && isHealthCompleted && isSportCompleted) {
                        DispatchQueue.main.async {
                            let healthSportData = YuchengHealthSportData(healthData: healthDataList, sportData: sportDataList)
                            let data = YuchengAllData(sleepData: sleepDataList, healthSportData: healthSportData)
                            completion(.success(data))
                            self.onAllData(YuchengAllDataEvent(data: data))
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
            isSportCompleted = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT, execute: {
            if (isHealthCompleted && isSleepCompleted && isSportCompleted) {
                return
            }
            DispatchQueue.main.async {
                self.onAllData(YuchengAllDataEvent(data: empty))
                self.onAllData(YuchengAllTimeOutEvent(isTimeout: true))
                completion(.success(empty))
            }
        })
    }
    
    func getDeviceSettings(completion: @escaping (Result<YuchengDeviceSettings?, any Error>) -> Void) {
        if ringState != YuchengDeviceState.connected && ringState != YuchengDeviceState.readWriteOK {
            completion(.failure(NoConnectionException()))
            return
        }
        if (currentDevice == nil) {
            completion(.success(nil))
        }
        
        var isCompleted = false
        
        do {
            let device = self.currentDevice ?? YCProduct.shared.currentPeripheral;
            let _ = device?.macAddress
            let _ = device?.name
            YCProduct.queryDeviceBasicInfo(device, completion: {state, response in
                if state == .succeed, let data = response as? YCDeviceBasicInfo {
                    let batteryValue = data.batteryPower
                    let firmwareVersion = data.mcuFirmware.version
                    let settings = YuchengDeviceSettings(batteryValue: Int64(batteryValue), firmwareVersion: firmwareVersion)
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
            let _ = selectedDevice?.macAddress
            YCProduct.deleteHealthData(selectedDevice, dataType: YCDeleteHealthDataType.sleep) { state, response in
                let isDeleted = state == YCProductState.succeed
                DispatchQueue.main.async {
                    completion(.success(isDeleted))
                }
                isCompleted = true
            }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
            isCompleted = true
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
    
    func deleteHealthSportData(completion: @escaping (Result<Bool, any Error>) -> Void) {
        var isHealthDeleted = false
        var isSportDeleted = false
        do {
            let selectedDevice = self.currentDevice ?? YCProduct.shared.currentPeripheral
            let _ = selectedDevice?.macAddress
            YCProduct.deleteHealthData(selectedDevice, dataType: YCDeleteHealthDataType.step) {
                state, response in
                let isDeleted = state == YCProductState.succeed
                isSportDeleted = isDeleted
                if (isHealthDeleted && isSportDeleted) {
                    DispatchQueue.main.async {
                        completion(.success(true))
                    }
                }
            }
            YCProduct.deleteHealthData(selectedDevice, dataType: YCDeleteHealthDataType.combinedData) { state, response in
                let isDeleted = state == YCProductState.succeed
                isHealthDeleted = isDeleted
                if (isHealthDeleted && isSportDeleted) {
                    DispatchQueue.main.async {
                        completion(.success(true))
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT, execute: {
            if (isHealthDeleted && isSportDeleted) {
                return
            }
            DispatchQueue.main.async {
                completion(.success(false))
            }
        })
    }
    
    func deleteAllData(completion: @escaping (Result<Bool, any Error>) -> Void) {
        var isHealthCompleted = false
        var isSleepCompleted = false
        var isSportCompleted = false
        do {
            let selectedDevice = self.currentDevice ?? YCProduct.shared.currentPeripheral
            let mac = selectedDevice?.macAddress
            YCProduct.deleteHealthData(selectedDevice, dataType: YCDeleteHealthDataType.step) { state, response in
                isSportCompleted = state == YCProductState.succeed
                if (isSleepCompleted && isHealthCompleted && isSportCompleted) {
                    DispatchQueue.main.async {
                        completion(.success(isSleepCompleted && isHealthCompleted && isSportCompleted))
                    }
                }
            }
            YCProduct.deleteHealthData(selectedDevice, dataType: YCDeleteHealthDataType.sleep) { state, response in
                isSleepCompleted = state == YCProductState.succeed
                if (isSleepCompleted && isHealthCompleted && isSportCompleted) {
                    DispatchQueue.main.async {
                        completion(.success(isSleepCompleted && isHealthCompleted && isSportCompleted))
                    }
                }
            }
            YCProduct.deleteHealthData(selectedDevice, dataType: YCDeleteHealthDataType.combinedData) { state, response in
                isHealthCompleted = state == YCProductState.succeed
                if (isSleepCompleted && isHealthCompleted && isSportCompleted) {
                    DispatchQueue.main.async {
                        completion(.success(isSleepCompleted && isHealthCompleted && isSportCompleted))
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT, execute: {
            if (isHealthCompleted && isSleepCompleted && isSportCompleted) {
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
            let selectedDevice = self.currentDevice ?? YCProduct.shared.currentPeripheral
            let mac = selectedDevice?.macAddress
            YCProduct.setDeviceReset(selectedDevice) { state, response in
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
    
    func updateFirmware(device: YuchengDevice, pathToFile: String, completion: @escaping (Result<Bool, any Error>) -> Void) {
        let curDevice = self.currentDevice
        if (curDevice == nil) {
            print("Device is nil")
            return
        }
        let path: String = assetPathHandler(pathToFile)
        self.scannedDevicesToUpdate.removeAll()
        self.filePathToUpdate = path
        self.reconnectMacAddress = curDevice!.macAddress
        self.isUpgradeCompleted = false
        self.isUiUpgradeCompleted = false
        
        otaUpdate(device: curDevice!, path: path, completion: completion)
    }
    
    private func otaUpdate(device: CBPeripheral, path: String, completion: @escaping (Result<Bool, any Error>) -> Void) {
        YCProduct.jlDeviceUpgradeFirmware(device, filePath: path) { state, progress, didSend in
            print("UPGRADE PROGRESS = " + String(progress))
            print("UPGRADE DID SEND = " + didSend.description)
            DispatchQueue.main.async {
                self.onUpdate(YuchengUpdateProgressEvent(progress: Double(progress)))
            }
            switch (state) {
            case .start:
                print("UPGRADE START")
                DispatchQueue.main.async {
                    let timeStamp = Int64(Date().timeIntervalSince1970).toMilliseconds()
                    self.onUpdate(YuchengUpdateStartEvent(startTimestamp: timeStamp))
                }
                break
            case .resourceUpdating:
                print("UPGRADE RESOURCE UPDATING")
                break
            case .updateResourceFinished:
                print("UPGRADE RESOURCE FINISHED")
                break
            case .uiUpdating:
                print("UPGRADE UI UPDATING")
                break
            case .updateUIFinished:
                if (self.isUiUpgradeCompleted) {
                    break
                }
                self.isUiUpgradeCompleted = true
                print("UPGRADE UI FINISHED")
                self.reconnectWithMacAddr(completion: completion)
                break
            case .upgrading:
                print("UPGRADE UPGRADING")
                break
            case .success:
                print("UPGRADE SUCCESS")
                if (!self.isUpgradeCompleted) {
                    completion(Result.success(true))
                    self.isUpgradeCompleted = true
                    DispatchQueue.main.async {
                        let timeStamp = Int64(Date().timeIntervalSince1970).toMilliseconds()
                        self.onUpdate(YuchengUpdateCompleteEvent(completeTimestamp: timeStamp))
                    }
                }
                break
            case .failed:
                print("UPGRADE FAILED")
                if (!self.isUpgradeCompleted) {
                    completion(.failure(UpgradeFirmwareError.failed("Failed to upgrade!")))
                    DispatchQueue.main.async {
                        self.onUpdate(YuchengUpdateErrorEvent(error: "Failed to upgrade!"))
                    }
                    self.isUpgradeCompleted = true
                }
                break
            @unknown default:
                print ("UPGRADE UNKNOWN")
                if (!self.isUpgradeCompleted) {
                    completion(.failure(UpgradeFirmwareError.failed("Unknown state")))
                    DispatchQueue.main.async {
                        self.onUpdate(YuchengUpdateErrorEvent(error: "Failed to upgrade!"))
                    }
                    self.isUpgradeCompleted = true
                }
                break
            }
        }
    }
    /// Connecting devices back
    func reconnectWithMacAddr(completion: @escaping (Result<Bool, any Error>) -> Void) {
        usleep(3_500_000)
        repeatScanJLCount = 0
        scanJLForceOtaDevice(completion: completion)
    }
    /// scan devices
    private func scanJLForceOtaDevice(completion: @escaping (Result<Bool, any Error>) -> Void) {
        repeatScanJLCount += 1
        if repeatScanJLCount >= REPEAT_SCAN_JL_FORCE_OTA_COUNT {
            return
        }
        // Search Device
        YCProduct.scanningDevice(delayTime: 6.0) { devices, error in
            if (devices.isEmpty) {
                self.currentDevice = YCProduct.shared.currentPeripheral
                if self.currentDevice != nil {
                    self.connectForceOtaDevice(completion: completion)
                }
            }
            for device in devices {
                if (!self.scannedDevicesToUpdate.contains(device)) {
                    print("Device found, try connect force ota device: \(device.macAddress)")
                    self.scannedDevicesToUpdate.append(device)
                    self.connectForceOtaDevice(completion: completion)
                }
            }
        }
    }
    /// Reconnect equipment
    private func connectForceOtaDevice(completion: @escaping (Result<Bool, any Error>) -> Void) {
        if (self.scannedDevicesToUpdate.isEmpty && self.currentDevice != nil) {
            let device = self.currentDevice!
            print("Device mac : Reconnect mac = " + device.macAddress.uppercased() + " : " + self.reconnectMacAddress.uppercased())
            if device.macAddress.uppercased() == self.reconnectMacAddress.uppercased() {
                YCProduct.connectDevice(device) { [weak self] state, error
                    in
                    print(state)
                    if (error != nil) {
                        print(error!)
                    }
                    if state == .connected {
                        self?.otaUpdate(device: device, path: self?.filePathToUpdate ?? "", completion: completion)
                    } else {
                        self?.scanJLForceOtaDevice(completion: completion)
                    }
                }
                return
            }
        } else {
            for device in scannedDevicesToUpdate {
                print("Device mac : Reconnect mac = " + device.macAddress.uppercased() + " : " + self.reconnectMacAddress.uppercased())
                if device.macAddress.uppercased() == self.reconnectMacAddress.uppercased() {
                    YCProduct.connectDevice(device) { [weak self] state, error
                        in
                        print(state)
                        if (error != nil) {
                            print(error!)
                        }
                        if state == .connected {
                            self?.otaUpdate(device: device, path: self?.filePathToUpdate ?? "", completion: completion)
                        } else {
                            self?.scanJLForceOtaDevice(completion: completion)
                        }
                    }
                    return
                }
            }
        }
        scanJLForceOtaDevice(completion: completion)
    }
    
    func getHealthMonitorInterval(completion: @escaping (Result<Int64?, any Error>) -> Void) {
        var isCompleted = false
        do {
            YCProduct.queryDeviceUserConfiguration { (state, result) in
                if isCompleted { return }
                if (state == YCProductState.succeed) {
                    let data = result as? YCProductUserConfiguration
                    if (data == nil) {
                        return
                    }
                    let monitoringInterval = data?.monitoringInterval ?? 0
                    DispatchQueue.main.async {
                        completion(.success(Int64(monitoringInterval)))
                    }
                } else {
                    completion(.success(nil))
                }
                isCompleted = true
            }
        } catch {
            isCompleted = true
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT, execute: {
            if isCompleted { return }
            completion(.success(nil))
        })
    }
    
    func setHealthMonitorInterval(interval: Int64, completion: @escaping (Result<Bool, any Error>) -> Void) {
        var isCompleted = false
        do {
            YCProduct.setDeviceHealthMonitoringMode(isEnable: true, interval: UInt8(interval), completion: {(state, result) in
                if state == YCProductState.succeed {
                    isCompleted = true
                    DispatchQueue.main.async {
                        completion(.success(true))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.success(false))
                    }
                }
            })
        } catch {
            isCompleted = true
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT, execute: {
            if isCompleted { return }
            completion(.success(false))
        })
    }
    
    func getRealTimeHealthRecord(completion: @escaping (Result<YuchengHealthSportData, any Error>) -> Void) {
        if ringState != YuchengDeviceState.connected && ringState != YuchengDeviceState.readWriteOK {
            completion(.failure(NoConnectionException()))
            return
        }
        var isCompleted = false
        bloodOxygenCompleter = Completer<Bool>();
        bloodPressureCompleter = Completer<Bool>();
        
        do {
            let device = self.currentDevice ?? YCProduct.shared.currentPeripheral;
            let _ = device?.macAddress
            let _ = device?.name
            YCProduct.realTimeDataUplod(device, isEnable: true, dataType: YCRealTimeDataType.step) { state, response in
                if (state == YCProductState.succeed) {
                    print("Successfully")
                } else {
                    print("Not successfully")
                }
            }
            YCProduct.controlMeasureHealthData(device, measureType: YCAppControlHealthDataMeasureType.single, dataType: YCAppControlMeasureHealthDataType.bloodPressure) { state, response in
            }
            bloodPressureCompleter?.future.sink(receiveCompletion: { result in
                switch (result) {
                case .finished:
                    YCProduct.controlMeasureHealthData(device, measureType: YCAppControlHealthDataMeasureType.single, dataType: YCAppControlMeasureHealthDataType.bloodOxygen) { state, response in
                    }
                case .failure(let error):
                    if (isCompleted) { return }
                    completion(.failure(error))
                    isCompleted = true
                    self.bloodPressureCancellables.removeAll()
                    self.bloodOxygens.removeAll()
                }
            }, receiveValue: { value in
            
            }).store(in: &bloodPressureCancellables)
            bloodOxygenCompleter?.future.sink(receiveCompletion: {result in
                switch (result) {
                case .finished:
                    DispatchQueue.main.async(execute: {
                        let startTimeStamp = Int64(Date().timeIntervalSince1970).toMilliseconds()
                        let bloodOxygenMean = self.calculateMean(collection: self.bloodOxygens)
                        let sbpMean = self.calculateMean(collection: self.sbps)
                        let dbpMean = self.calculateMean(collection: self.dbps)
                        let heartRateMean = self.calculateMean(collection: self.heartRates)
                        let healthData = YuchengHealthData(heartValue: heartRateMean, hrvValue: 0, cvrrValue: 0, OOValue: bloodOxygenMean, stepValue: self.steps, DBPValue: dbpMean, tempIntValue: 0, tempFloatValue: 0, startTimestamp: startTimeStamp, SBPValue: sbpMean, respiratoryRateValue: 0, bodyFatIntValue: 0, bodyFatFloatValue: 0, bloodSugarValue: 0)
                        let sportData = YuchengSportData(startTimeStamp: startTimeStamp, endTimeStamp: startTimeStamp, distance: self.distance, steps: self.steps, calories: self.calories)
                        let data = YuchengHealthSportData(healthData: [healthData], sportData: [sportData])
                        if (isCompleted) { return }
                        completion(.success(data))
                        isCompleted = true
                        self.bloodPressureCancellables.removeAll()
                        self.oxygenCancellables.removeAll()
                        self.sbps.removeAll()
                        self.dbps.removeAll()
                        self.heartRates.removeAll()
                        self.bloodOxygens.removeAll()
                    })
                case .failure(let error):
                    if (isCompleted) { return }
                    DispatchQueue.main.async(execute: {
                        completion(.failure(error))
                    })
                    isCompleted = true
                    self.bloodPressureCancellables.removeAll()
                    self.oxygenCancellables.removeAll()
                    self.sbps.removeAll()
                    self.dbps.removeAll()
                    self.heartRates.removeAll()
                    self.bloodOxygens.removeAll()
                }
            }, receiveValue: { value in
            }).store(in: &oxygenCancellables)
        } catch {
            if (isCompleted) { return }
            DispatchQueue.main.async(execute: {
                completion(.failure(error))
            })
            isCompleted = true
            self.bloodPressureCancellables.removeAll()
            self.oxygenCancellables.removeAll()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(REALTIME_TIMEOUT * 2), execute: {
            if (isCompleted) { return }
            completion(.failure(RealTimeMeasurementFailedException()))
            self.stopMeasurementByType(YCAppControlMeasureHealthDataType.bloodPressure)
            self.stopMeasurementByType(YCAppControlMeasureHealthDataType.bloodOxygen)
            isCompleted = true
            self.bloodPressureCancellables.removeAll()
            self.oxygenCancellables.removeAll()
        })
    }
    
    func startMeasurementBloodOxygen(completion: @escaping (Result<Int64?, any Error>) -> Void) {
        if ringState != YuchengDeviceState.connected && ringState != YuchengDeviceState.readWriteOK {
            completion(.failure(NoConnectionException()))
            return
        }
        var isCompleted = false
        bloodOxygenCompleter = Completer<Bool>();

        do {
            let device = self.currentDevice ?? YCProduct.shared.currentPeripheral;
            let _ = device?.macAddress
            let _ = device?.name
            YCProduct.controlMeasureHealthData(device, measureType: YCAppControlHealthDataMeasureType.single, dataType: YCAppControlMeasureHealthDataType.bloodOxygen) { state, response in
            }
            bloodOxygenCompleter?.future.sink(receiveCompletion: {result in
                switch (result) {
                case .finished:
                    break
                case .failure(let error):
                    if (isCompleted) { return }
                    DispatchQueue.main.async(execute: {
                        completion(.failure(error))
                    })
                    isCompleted = true
                    self.oxygenCancellables.removeAll()
                    self.bloodOxygens.removeAll()
                }
            }, receiveValue: { value in
                DispatchQueue.main.async(execute: {
                    let bloodOxygenMean = self.calculateMean(collection: self.bloodOxygens)
                    if (isCompleted) { return }
                    if (value) {
                        completion(.success(bloodOxygenMean))
                    } else {
                        completion(.success(nil))
                    }
                    isCompleted = true
                    self.oxygenCancellables.removeAll()
                    self.bloodOxygens.removeAll()
                })
            }).store(in: &oxygenCancellables)
        } catch {
            if (isCompleted) { return }
            DispatchQueue.main.async(execute: {
                completion(.failure(error))
            })
            isCompleted = true
            self.oxygenCancellables.removeAll()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(REALTIME_TIMEOUT), execute: {
            if (isCompleted) { return }
            completion(.failure(RealTimeMeasurementFailedException()))
            isCompleted = true
            self.bloodOxygens.removeAll()
            self.stopMeasurementByType(YCAppControlMeasureHealthDataType.bloodOxygen)
            self.oxygenCancellables.removeAll()
        })
    }
    
    func startMeasurementHeart(completion: @escaping (Result<Int64?, any Error>) -> Void) {
        if ringState != YuchengDeviceState.connected && ringState != YuchengDeviceState.readWriteOK {
            completion(.failure(NoConnectionException()))
            return
        }
        var isCompleted = false
        bloodPressureCompleter = Completer<Bool>();
        
        do {
            let device = self.currentDevice ?? YCProduct.shared.currentPeripheral;
            let _ = device?.macAddress
            let _ = device?.name
            YCProduct.controlMeasureHealthData(device, measureType: YCAppControlHealthDataMeasureType.single, dataType: YCAppControlMeasureHealthDataType.bloodPressure) { state, response in
            }
            bloodPressureCompleter?.future.sink(receiveCompletion: { result in
                switch (result) {
                case .finished:
                    break;
                case .failure(let error):
                    if (isCompleted) { return }
                    DispatchQueue.main.async(execute: {
                        completion(.failure(error))
                    })
                    isCompleted = true
                    self.bloodPressureCancellables.removeAll()
                    self.heartRates.removeAll()
                    self.sbps.removeAll()
                    self.dbps.removeAll()
                }}, receiveValue: { value in
                    DispatchQueue.main.async(execute: {
                        if (isCompleted) { return }
                        let heartRateMean = self.calculateMean(collection: self.heartRates)
                        if (value) {
                            completion(.success(heartRateMean))
                        } else {
                            completion(.success(nil))
                        }
                        isCompleted = true
                        self.bloodPressureCancellables.removeAll()
                        self.heartRates.removeAll()
                        self.sbps.removeAll()
                        self.dbps.removeAll()
                    });
            }).store(in: &bloodPressureCancellables)
        } catch {
            if (isCompleted) { return }
            completion(.failure(error))
            isCompleted = true
            self.bloodPressureCancellables.removeAll()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(REALTIME_TIMEOUT), execute: {
            if (isCompleted) { return }
            self.heartRates.removeAll()
            self.sbps.removeAll()
            self.dbps.removeAll()
            completion(.failure(RealTimeMeasurementFailedException()))
            isCompleted = true
            self.stopMeasurementByType(YCAppControlMeasureHealthDataType.bloodPressure)
            self.bloodPressureCancellables.removeAll()
        })
    }
    
    func startMeasurementBloodPressure(completion: @escaping (Result<RealTimeBloodPressure?, any Error>) -> Void) {
        if ringState != YuchengDeviceState.connected && ringState != YuchengDeviceState.readWriteOK {
            completion(.failure(NoConnectionException()))
            return
        }
        var isCompleted = false
        bloodPressureCompleter = Completer<Bool>();
        
        do {
            let device = self.currentDevice ?? YCProduct.shared.currentPeripheral;
            let _ = device?.macAddress
            YCProduct.controlMeasureHealthData(device, measureType: YCAppControlHealthDataMeasureType.single, dataType: YCAppControlMeasureHealthDataType.bloodPressure) { state, response in
            }
            bloodPressureCompleter?.future.sink(receiveCompletion: { result in
                switch (result) {
                case .finished:
                    break;
                case .failure(let error):
                    if (isCompleted) { return }
                    DispatchQueue.main.async(execute: {
                        completion(.failure(error))
                    })
                    isCompleted = true
                    self.bloodPressureCancellables.removeAll()
                    self.sbps.removeAll()
                    self.dbps.removeAll()
                    self.heartRates.removeAll()
                }
            }, receiveValue: { value in
                DispatchQueue.main.async(execute: {
                    if (isCompleted) { return }
                    let sbpMean = self.calculateMean(collection: self.sbps)
                    let dbpMean = self.calculateMean(collection: self.dbps)
                    if (value) {
                        completion(.success(RealTimeBloodPressure(dbp: Int64(dbpMean), sbp: Int64(sbpMean))))
                    } else {
                        completion(.success(nil))
                    }
                    isCompleted = true
                    self.bloodPressureCancellables.removeAll()
                    self.sbps.removeAll()
                    self.dbps.removeAll()
                    self.heartRates.removeAll()
                })
            }).store(in: &bloodPressureCancellables)
        } catch {
            if (isCompleted) { return }
            DispatchQueue.main.async(execute: {
                completion(.failure(error))
            })
            isCompleted = true
            self.bloodPressureCancellables.removeAll()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(REALTIME_TIMEOUT), execute: {
            if (isCompleted) { return }
            completion(.failure(RealTimeMeasurementFailedException()))
            isCompleted = true
            self.sbps.removeAll()
            self.dbps.removeAll()
            self.heartRates.removeAll()
            self.stopMeasurementByType(YCAppControlMeasureHealthDataType.bloodPressure)
            self.bloodPressureCancellables.removeAll()
        })
    }
    
    func stopMeasurementBloodOxygen(completion: @escaping (Result<Bool, any Error>) -> Void) {
        var isCompleted = false
        
        do {
            let device = self.currentDevice ?? YCProduct.shared.currentPeripheral;
            let _ = device?.macAddress
            YCProduct.controlMeasureHealthData(device, measureType: YCAppControlHealthDataMeasureType.off, dataType: YCAppControlMeasureHealthDataType.bloodOxygen) { state, response in
                if (isCompleted) { return }
                isCompleted = true
                let result = state == .succeed
                if (result) {
                    self.bloodOxygenCompleter?.complete(false)
                }
                DispatchQueue.main.async(execute: {
                    completion(.success(result))
                })
                self.oxygenCancellables.removeAll()
                self.bloodOxygens.removeAll()
            }
        } catch {
            if (isCompleted) { return }
            DispatchQueue.main.async(execute: {
                completion(.failure(error))
            })
            isCompleted = true
            self.oxygenCancellables.removeAll()
            self.bloodOxygens.removeAll()
        }
    }
    
    func stopMeasurementBloodPressure(completion: @escaping (Result<Bool, any Error>) -> Void) {
        var isCompleted = false
        
        do {
            let device = self.currentDevice ?? YCProduct.shared.currentPeripheral;
            let _ = device?.macAddress
            YCProduct.controlMeasureHealthData(device, measureType: YCAppControlHealthDataMeasureType.off, dataType: YCAppControlMeasureHealthDataType.bloodPressure) { state, response in
                if (isCompleted) { return }
                isCompleted = true
                let result = state == .succeed
                if (result) {
                    self.bloodPressureCompleter?.complete(false)
                }
                DispatchQueue.main.async(execute: {
                    completion(.success(result))
                })
                self.bloodPressureCancellables.removeAll()
                self.dbps.removeAll()
                self.sbps.removeAll()
                self.heartRates.removeAll()
            }
        } catch {
            if (isCompleted) { return }
            DispatchQueue.main.async(execute: {
                completion(.failure(error))
            })
            isCompleted = true
            self.bloodPressureCancellables.removeAll()
            self.dbps.removeAll()
            self.sbps.removeAll()
            self.heartRates.removeAll()
        }
    }
    
    func stopMeasurementHeart(completion: @escaping (Result<Bool, any Error>) -> Void) {
        var isCompleted = false
        
        do {
            let device = self.currentDevice ?? YCProduct.shared.currentPeripheral;
            let _ = device?.macAddress
            YCProduct.controlMeasureHealthData(device, measureType: YCAppControlHealthDataMeasureType.off, dataType: YCAppControlMeasureHealthDataType.bloodPressure) { state, response in
                if (isCompleted) { return }
                isCompleted = true
                let result = state == .succeed
                if (result) {
                    self.bloodPressureCompleter?.complete(false)
                }
                DispatchQueue.main.async(execute: {
                    completion(.success(result))
                })
                self.bloodPressureCancellables.removeAll()
                self.dbps.removeAll()
                self.sbps.removeAll()
                self.heartRates.removeAll()
            }
        } catch {
            if (isCompleted) { return }
            DispatchQueue.main.async(execute: {
                completion(.failure(error))
            })
            isCompleted = true
            self.bloodPressureCancellables.removeAll()
            self.dbps.removeAll()
            self.sbps.removeAll()
            self.heartRates.removeAll()
        }
    }
    
    private func stopMeasurementByType(_ type: YCAppControlMeasureHealthDataType) {
        let device = self.currentDevice ?? YCProduct.shared.currentPeripheral;
        let _ = device?.macAddress
        YCProduct.controlMeasureHealthData(device, measureType: YCAppControlHealthDataMeasureType.off, dataType: type) { state, response in
            
        }
    }
    
    private func calculateMean(collection: [Int64]) -> Int64 {
        var sum = 0.0
        for item in collection {
            sum += Double(item)
        }
        var count = Double(collection.count)
        count = count < 1 ? 1 : count
        let mean = (sum / count).rounded(.toNearestOrAwayFromZero)
        return Int64(mean)
    }
    
    func calibrateBloodPressure(sbp: Int64, dbp: Int64, completion: @escaping (Result<Bool, any Error>) -> Void) {
        var isCompleted = false
        do {
            let device = self.currentDevice ?? YCProduct.shared.currentPeripheral;
            let _ = device?.macAddress
            YCProduct.deviceBloodPressureCalibration(device, systolicBloodPressure: UInt8(sbp), diastolicBloodPressure: UInt8(dbp)) { state, response in
                if (isCompleted) {
                    return
                }
                let result = state == YCProductState.succeed
                completion(.success(result))
                isCompleted = true
            }
        } catch {
            if (isCompleted) {
                return
            }
            completion(Result.failure(error))
            isCompleted = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + TIME_TO_TIMEOUT, execute: {
            if (isCompleted) {
                return
            }
            completion(Result.success(false))
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
