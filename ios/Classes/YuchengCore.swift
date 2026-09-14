//
//  YuchengCore.swift
//  Pods
//
//  Created by Maxim Zarechnev on 20.03.2026.
//

import YCProductSDK
import CoreBluetooth
import Combine

typealias DeviceHandler = (any YuchengDeviceEvent) -> Void
typealias StateHandler = (any YuchengDeviceStateEvent) -> Void
typealias SleepHandler = (any YuchengSleepEvent) -> Void
typealias HealthHandler = (any YuchengHealthEvent) -> Void
typealias AllDataHandler = (any YuchengAllEvent) -> Void
typealias UpdateHandler = (any YuchengUpdateEvent) -> Void
typealias AssetPathHandler = (String) -> String;

public class YuchengCore {
    
    static let shared = YuchengCore()
    
    static let TIME_TO_TIMEOUT = 15.0;
    static let TIME_TO_TIMEOUT_RESET = 30.0;
    static let TIME_TO_SCAN = 15.0;
    static let TIME_TO_SCAN_TIMEOUT = 20.0;
    static let TIME_TO_RECONNECT = 20;
    static let TIME_TO_QUERY_MAC_ADDR = 10;
    var ringState: YuchengDeviceState = YuchengDeviceState.unknown
    private var onState: StateHandler? = nil
    private var onDevice: DeviceHandler? = nil
    var currentDevice: CBPeripheral? = nil
    private var scannedDevices: [CBPeripheral] = [];
    var index = 0
    
    var reconnectMacAddress: String = ""
    var scannedDevicesToUpdate: [CBPeripheral] = [];
    /// Limit on number of repeated scans
    static let REPEAT_SCAN_JL_FORCE_OTA_COUNT = 10
    static let REALTIME_TIMEOUT = 90;
    /// Number of repeated scans
    var repeatScanJLCount: Int = 0
    /// Connect back to device address
    var filePathToUpdate: String = ""
    var isUpgradeCompleted = false
    var isUiUpgradeCompleted = false
    
    private let initQueue = DispatchQueue(label: "YcInitQueue.lock")
    
    private var isInit = false
    
    private init() {}
    
    deinit {
        NotificationCenter.default.removeObserver(
            self,
            name: YCProduct.deviceStateNotification,
            object: nil
        )
    }
    
    @objc func deviceStateChange(_ ntf: Notification) {
        guard let info = ntf.userInfo as? [String: Any],
              let state = info[YCProduct.connecteStateKey] as? YCProductState else {
            return
        }
        print("deviceStateChange: state = \(state)")
        if (state == YCProductState.connected) {
            self.ringState = YuchengDeviceState.connected
            self.onState?(YuchengDeviceStateDataEvent(state: YuchengDeviceState.connected))
        } else if (state == YCProductState.connectedFailed) {
            self.ringState = YuchengDeviceState.connectedFailed
            self.onState?(YuchengDeviceStateDataEvent(state: YuchengDeviceState.connectedFailed))
        } else if (state == YCProductState.disconnected) {
            self.ringState = YuchengDeviceState.disconnected
            self.onState?(YuchengDeviceStateDataEvent(state: YuchengDeviceState.disconnected))
        } else if (state == YCProductState.unavailable) {
            self.ringState = YuchengDeviceState.unavailable
            self.onState?(YuchengDeviceStateDataEvent(state: YuchengDeviceState.unavailable))
        } else if (state == YCProductState.timeout) {
            self.ringState = YuchengDeviceState.timeOut
            self.onState?(YuchengDeviceStateDataEvent(state: YuchengDeviceState.timeOut))
        } else if (state == YCProductState.succeed) {
            self.ringState = YuchengDeviceState.readWriteOK
            self.onState?(YuchengDeviceStateDataEvent(state: YuchengDeviceState.readWriteOK))
            currentDevice = YCProduct.shared.currentPeripheral
            if (currentDevice != nil && !(currentDevice?.macAddress.isEmpty ?? true)) {
                self.onDevice?(YuchengDeviceDataEvent(index: Int64(self.index), mac: currentDevice!.macAddress, isReconnected: true, deviceName: currentDevice!.name ?? ""))
            }
        } else {
            self.ringState = YuchengDeviceState.unknown
            self.onState?(YuchengDeviceStateDataEvent(state: YuchengDeviceState.unknown))
        }
        print("STATE: " + state.toString)
    }
    
    func initialize(onState: StateHandler? = nil, onDevice: DeviceHandler? = nil) {
        initQueue.sync {
            if (isInit) {
                return
            }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.deviceStateChange(_:)),
                name: YCProduct.deviceStateNotification,
                object: nil
            )
            self.onState = onState
            self.onDevice = onDevice
            isInit = true
        }
    }
    
    func scanDevices(scanTimeInSeconds: Double?, onDevice: DeviceHandler? = nil) -> AnyPublisher<[YuchengDevice], Error> {
        let completer = Completer<[YuchengDevice]>()
        let lastConnectedDevice = YCProduct.shared.currentPeripheral;
        var ycDevices: [YuchengDevice] = [];
        do {
            YCProduct.scanningDevice(delayTime: scanTimeInSeconds ?? YuchengCore.TIME_TO_SCAN) { devices, error in
                if (error != nil) {
                    onDevice?(YuchengDeviceCompleteEvent(completed: false))
                    completer.complete(ycDevices)
                } else {
                    self.scannedDevices = devices;
                    for device in devices {
                        DispatchQueue.main.async {
                            print("UUID DEVICE = " + device.identifier.uuidString)
                            let deviceMac = device.macAddress
                            let deviceName = device.name
                            let isReconnected = lastConnectedDevice?.macAddress == deviceMac && self.isConnected();
                            self.currentDevice = isReconnected ? device : nil;
                            if (!ycDevices.contains(where: { dev in
                                dev.uuid == deviceMac || dev.deviceName == deviceName
                            })) {
                                let ycDevice = YuchengDevice(index: Int64(self.index), deviceName: device.name ?? "", uuid: device.macAddress, isReconnected: isReconnected)
                                onDevice?(YuchengDeviceDataEvent(index: Int64(self.index), mac: deviceMac, isReconnected: ycDevice.isReconnected, deviceName: deviceName ?? device.deviceModel))
                                self.index += 1
                                ycDevices.append(ycDevice)
                                print("SCAN DEVICES : DEVICE = " + ycDevice.uuid + ", " + ycDevice.deviceName)
                            }
                        }
                    }
                }
            }
        } catch (let e) {
            onDevice?(YuchengDeviceCompleteEvent(completed: false))
            completer.completeError(e)
        }

        
        DispatchQueue.main.asyncAfter(deadline: .now() + YuchengCore.TIME_TO_SCAN_TIMEOUT) {
            if (completer.isCompleted) {
                return;
            }
            if (ycDevices.isEmpty) {
                onDevice?(YuchengDeviceTimeOutEvent(isTimeout: true))
            } else {
                onDevice?(YuchengDeviceCompleteEvent(completed: true))
            }
            completer.complete(ycDevices)
        }
        
        return completer.future
    }
    
    func connect(device: YuchengDevice, connectTimeInSeconds: Int64?, onDevice: DeviceHandler? = nil) -> AnyPublisher<Bool, Error> {
        let timeout = connectTimeInSeconds ?? Int64((YuchengCore.TIME_TO_TIMEOUT + 10))
        let completer = Completer<Bool>()
        if (self.currentDevice != nil) {
            if (device.deviceName == self.currentDevice?.name || device.uuid == self.currentDevice?.macAddress && isConnected()) {
                completer.complete(true)
                return completer.future;
            }
        }
        
        if (self.scannedDevices.isEmpty) {
            let sub = scanDevices(scanTimeInSeconds: Double(timeout) - 5)
            YuchengCancelableStore.shared.subscribe(sub) { result in
                switch (result) {
                case .finished:
                    if (self.scannedDevices.isEmpty) {
                        completer.completeError(NoDeviceError.noDevice("No device found"))
                    }
                    break;
                case .failure(let e):
                    completer.completeError(e)
                    break;
                }
            } receiveValue: { devices in
                if (devices.isEmpty) {
                    completer.completeError(NoDeviceError.noDevice("No device found"))
                    return
                }
                    let foundDevice = devices.first { ycDevice in
                        device.deviceName == ycDevice.deviceName || device.uuid == ycDevice.uuid
                    }
                    if (foundDevice == nil) {
                        completer.completeError(NoDeviceError.noDevice("No device found"))
                        return
                    }
                    let conSub = self.internalConnect(device: foundDevice!, timeout: Int(timeout), onDevice: onDevice)
                    YuchengCancelableStore.shared.subscribe(conSub) { conRes in
                        switch (conRes) {
                        case .failure(let e):
                            completer.completeError(e)
                        case .finished:
                            break;
                        }
                    } receiveValue: { conRes in
                        completer.complete(conRes)
                    }
            }


            return completer.future
        }
        
    
        let sub = self.internalConnect(device: device, timeout: Int(timeout) - 5, onDevice: onDevice)
        YuchengCancelableStore.shared.subscribe(sub) { result in
            switch (result) {
            case .failure(let e):
                completer.completeError(e)
            case .finished:
                break;
            }
        } receiveValue: { result in
            completer.complete(result)
        }


        return completer.future
    }
    
    private func internalConnect(device: YuchengDevice, timeout: Int, onDevice: DeviceHandler? = nil) -> AnyPublisher<Bool, Error> {
        let completer = Completer<Bool>()
        self.currentDevice = scannedDevices.first(where: { scannedDevice in
            scannedDevice.name == device.deviceName
        })
        
        if (self.currentDevice == nil) {
            self.currentDevice = YCProduct.shared.currentPeripheral;
        }
        
        if (YuchengCore.shared.currentDevice == nil) {
            completer.completeError(NoDeviceError.noDevice("Current device is nil"))
            return completer.future
        }
        
        YCProduct.connectDevice(self.currentDevice!) { state, error in
            if let error = error {
                completer.completeError(error)
            } else {
                if state == .connected {
                    let device = YCProduct.shared.currentPeripheral;
                    let mac = device?.macAddress ?? "";
                    let name = device?.name ?? "";
                    completer.complete(true)
                    if (device != nil) {
                        YuchengCore.shared.currentDevice = device
                        let isOtaForce = YCProduct.isJLDeviceForceOTA()
                        if (isOtaForce) {
                            self.reconnectMacAddress = mac
                            self.connectForceOtaDevice(onUpdate: nil) { res in }
                        }
                        DispatchQueue.main.async(execute:  {
                            onDevice?(YuchengDeviceDataEvent(index: Int64(self.index), mac: mac, isReconnected: false, deviceName: name))
                        })
                    }
                } else {
                    completer.complete(false)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(Int(timeout))) {
            if (completer.isCompleted) {
                return;
            }
            self.onState?(YuchengDeviceStateTimeOutEvent(isTimeout: true))
            completer.complete(false)
        }
        return completer.future
    }
    
    func reconnect(uuid: String?, reconnectTimeInSeconds: Int64?, onDevice: DeviceHandler? = nil) -> AnyPublisher<Bool, Error> {
        let completer = Completer<Bool>()
        if (uuid != nil && self.currentDevice != nil && self.currentDevice?.macAddress == uuid && isConnected()) {
            print("RECONNECT! uuid != nil && self.currentDevice != nil && self.currentDevice.macAddress == uuid && isConnected()")
            let device = YuchengCore.shared.currentDevice
            let deviceMacAddress = device?.macAddress
            let isReconnected = deviceMacAddress != nil
            let ycDevice = YuchengDevice(index: Int64(self.index), deviceName: device?.name ?? "", uuid: deviceMacAddress ?? "", isReconnected: isReconnected)
            DispatchQueue.main.async {
                onDevice?(YuchengDeviceDataEvent(index: ycDevice.index, mac: ycDevice.uuid, isReconnected: ycDevice.isReconnected, deviceName: ycDevice.deviceName))
            }
            completer.complete(true)
            return completer.future
        }
        do {
            let isOtaForce = YCProduct.isJLDeviceForceOTA()
            if (isOtaForce) {
                YuchengCore.shared.currentDevice = YCProduct.shared.currentPeripheral
                self.reconnectMacAddress = YuchengCore.shared.currentDevice?.macAddress ?? uuid ?? ""
                self.connectForceOtaDevice(onUpdate: nil) { res in }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(YuchengCore.TIME_TO_QUERY_MAC_ADDR)) {
                YCProduct.queryDeviceMacAddress { state, response in
                    YuchengCore.shared.currentDevice = YCProduct.shared.currentPeripheral
                    if state == YCProductState.succeed,
                       let macAddress = response as? String {
                        print("Reconnect: state == success")
                        YuchengCore.shared.currentDevice = YCProduct.shared.currentPeripheral
                        let device = YuchengCore.shared.currentDevice
                        let deviceMacAddress = device?.macAddress
                        let isReconnected = deviceMacAddress != nil
                        let isDevice = device != nil
                        if (isDevice) {
                            print("Reconnect: state == success, isDevice = true")
                            let ycDevice = YuchengDevice(index: Int64(self.index), deviceName: device?.name ?? "", uuid: deviceMacAddress ?? macAddress, isReconnected: isReconnected)
                            DispatchQueue.main.async {
                                self.onState?(YuchengDeviceStateDataEvent(state: .readWriteOK))
                                onDevice?(YuchengDeviceDataEvent(index: ycDevice.index, mac: ycDevice.uuid, isReconnected: ycDevice.isReconnected, deviceName: ycDevice.deviceName))
                            }
                            completer.complete(isDevice)
                            self.index += 1
                        } else {
                            print("Reconnect: state == success, isDevice = false, try forward connect")
                            YCProduct.connectDevice(YuchengCore.shared.currentDevice!) { state, error in
                                if let error = error {
                                    print("Reconnect: state == success, forward connect with error")
                                    completer.completeError(error)
                                } else {
                                    if state == .connected {
                                        print("Reconnect: state == success, connected!")
                                        let device = YCProduct.shared.currentPeripheral;
                                        let mac = device?.macAddress ?? "";
                                        let name = device?.name ?? "";
                                        completer.complete(true)
                                        if (device != nil) {
                                            YuchengCore.shared.currentDevice = device
                                            let isOtaForce = YCProduct.isJLDeviceForceOTA()
                                            if (isOtaForce) {
                                                self.reconnectMacAddress = mac
                                                self.connectForceOtaDevice(onUpdate: nil) { res in }
                                            }
                                            DispatchQueue.main.async(execute:  {
                                                self.onState?(YuchengDeviceStateDataEvent(state: .readWriteOK))
                                                onDevice?(YuchengDeviceDataEvent(index: Int64(self.index), mac: mac, isReconnected: true, deviceName: name))
                                            })
                                            self.index += 1
                                        }
                                    } else {
                                        print("Reconnect: state == success, cant connect")
                                        if (!completer.isCompleted) {
                                            completer.complete(false)
                                        }
                                    }
                                }
                                self.index += 1
                            }
                        }
                    } else {
                        print("Reconnect: state != success")
                        if YuchengCore.shared.currentDevice == nil {
                            print("Reconnect: state != success, currentDevice == nil")
                            completer.complete(false)
                            return
                        }
                        print("Reconnect: state != success, try forward connect")
                        YCProduct.connectDevice(YuchengCore.shared.currentDevice!) { state, error in
                            if let error = error {
                                print("Reconnect: state != success, try forward connect, done = error")
                                completer.completeError(error)
                            } else {
                                if state == .connected {
                                    print("Reconnect: state != success, try forward connect, connected!")
                                    let device = YCProduct.shared.currentPeripheral;
                                    let mac = device?.macAddress ?? "";
                                    let name = device?.name ?? "";
                                    completer.complete(true)
                                    if (device != nil) {
                                        YuchengCore.shared.currentDevice = device
                                        let isOtaForce = YCProduct.isJLDeviceForceOTA()
                                        if (isOtaForce) {
                                            self.reconnectMacAddress = mac
                                            self.connectForceOtaDevice(onUpdate: nil) { res in }
                                        }
                                        DispatchQueue.main.async(execute:  {
                                            self.onState?(YuchengDeviceStateDataEvent(state: .readWriteOK))
                                            onDevice?(YuchengDeviceDataEvent(index: Int64(self.index), mac: mac, isReconnected: true, deviceName: name))
                                        })
                                        self.index += 1
                                    }
                                } else {
                                    print("Reconnect: state != success, try forward connect, NOT connected!")
                                    if (!completer.isCompleted) {
                                        completer.complete(false)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            completer.completeError(error)
        }
        let seconds = reconnectTimeInSeconds == nil ? DispatchTimeInterval.seconds(YuchengCore.TIME_TO_RECONNECT) : DispatchTimeInterval.seconds(Int(reconnectTimeInSeconds!))
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: {
            if (completer.isCompleted) {
                return
            }
            completer.complete(false)
        })
        
        return completer.future
    }
    
    func disconnect() -> AnyPublisher<Void, Error> {
        let completer = Completer<Void>()
        YCProduct.disconnectDevice(YuchengCore.shared.currentDevice ?? YCProduct.shared.currentPeripheral) { state, error in
            if let error = error {
                completer.completeError(error)
            } else {
                completer.complete(())
            }
            YuchengCore.shared.currentDevice = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if (completer.isCompleted) {
                return;
            }
            completer.complete(())
        }
        return completer.future
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
    
    func getSleepData(startTimestamp: Int64?, endTimestamp: Int64?, sleepConverter: YuchengSleepDataConverter, onSleepData: SleepHandler? = nil) -> AnyPublisher<[YuchengSleepData], Error> {
        let completer = Completer<[YuchengSleepData]>()
        let safety = HistoryReadSafety.sleep
        guard safety.begin() else {
            completer.completeError(NSError(domain: "YuchengHistory", code: 3, userInfo: [NSLocalizedDescriptionKey: "History clear is in progress"]))
            return completer.future
        }
        var finished = false
        func finish(_ result: Result<[YuchengSleepData], Error>, complete: Bool) {
            guard !finished else { return }
            finished = true
            safety.finish(complete: complete)
            switch result {
            case .success(let data):
                completer.complete(data)
                data.forEach { onSleepData?(YuchengSleepDataEvent(sleepData: $0)) }
            case .failure(let error):
                completer.completeError(error)
            }
        }
        if !isConnected() {
            finish(.failure(NoConnectionException()), complete: false)
            return completer.future
        }
        let defaults = getDefaultStartAndEndDate()
        let start = startTimestamp ?? defaults.start
        let end = endTimestamp ?? defaults.end
        guard start < end else {
            let message = "Start timestamp must precede end timestamp"
            onSleepData?(YuchengSleepErrorEvent(error: message))
            finish(.failure(NSError(domain: "YuchengHistory", code: 1, userInfo: [NSLocalizedDescriptionKey: message])), complete: false)
            return completer.future
        }
        let device = currentDevice ?? YCProduct.shared.currentPeripheral
        YCProduct.queryHealthData(device, dataType: .sleep) { state, response in
            DispatchQueue.main.async {
                guard !finished else { return }
                if state == .noRecord {
                    finish(.success([]), complete: true)
                } else if state == .succeed, let rows = response as? [YCHealthDataSleep] {
                    let all = rows.map { sleepConverter.convert(sleepDataFromDevice: $0) }
                    let data = all.filter { $0.startTimeStamp >= start && $0.endTimeStamp <= end }
                    finish(.success(data), complete: data.count == all.count)
                } else {
                    let error = NSError(domain: "YuchengHistory", code: 2, userInfo: [NSLocalizedDescriptionKey: "Sleep history query failed: \(state)"])
                    onSleepData?(YuchengSleepErrorEvent(error: error.localizedDescription))
                    finish(.failure(error), complete: false)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + YuchengCore.TIME_TO_TIMEOUT) {
            guard !finished else { return }
            onSleepData?(YuchengSleepTimeOutEvent(isTimeout: true))
            finish(.failure(TimeoutError()), complete: false)
        }
        return completer.future.handleEvents(receiveCancel: {
            DispatchQueue.main.async {
                finish(.failure(CancellationError()), complete: false)
            }
        }).eraseToAnyPublisher()
    }

    func getHealthData(startTimestamp: Int64?, endTimestamp: Int64?, sportConverter: YuchengSportDataConverter, healthConverter: YuchengHealthDataConverter, onHealth: HealthHandler? = nil) -> AnyPublisher<YuchengHealthSportData, Error> {
        let completer = Completer<YuchengHealthSportData>()
        let safety = HistoryReadSafety.health
        guard safety.begin() else {
            completer.completeError(NSError(domain: "YuchengHistory", code: 3, userInfo: [NSLocalizedDescriptionKey: "History clear is in progress"]))
            return completer.future
        }
        var finished = false
        var healthDone = false
        var sportDone = false
        var health: [YuchengHealthData] = []
        var sport: [YuchengSportData] = []
        var errors: [Error] = []
        var filtered = false
        func finish(cancelled: Bool = false) {
            guard !finished else { return }
            finished = true
            let complete = healthDone && sportDone && errors.isEmpty && !cancelled
            safety.finish(complete: complete && !filtered)
            if cancelled {
                completer.completeError(CancellationError())
            } else if complete || !health.isEmpty || !sport.isEmpty {
                let data = YuchengHealthSportData(healthData: health, sportData: sport)
                completer.complete(data)
                onHealth?(YuchengHealthDataEvent(healthData: data))
            } else {
                completer.completeError(errors.first ?? TimeoutError())
            }
        }
        if !isConnected() {
            errors.append(NoConnectionException())
            finish()
            return completer.future
        }
        let defaults = getDefaultStartAndEndDate()
        let start = startTimestamp ?? defaults.start
        let end = endTimestamp ?? defaults.end
        guard start < end else {
            let message = "Start timestamp must precede end timestamp"
            onHealth?(YuchengHealthErrorEvent(error: message))
            errors.append(NSError(domain: "YuchengHistory", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
            finish()
            return completer.future
        }
        let device = currentDevice ?? YCProduct.shared.currentPeripheral
        YCProduct.queryHealthData(device, dataType: .step) { state, response in
            DispatchQueue.main.async {
                guard !finished && !sportDone else { return }
                sportDone = true
                if state == .noRecord {
                    sport = []
                } else if state == .succeed, let rows = response as? [YCHealthDataStep] {
                    let all = rows.map { sportConverter.convert(sportDataFromDevice: $0) }
                    sport = all.filter { $0.startTimeStamp >= start && $0.endTimeStamp <= end }
                    filtered = filtered || sport.count != all.count
                } else {
                    errors.append(NSError(domain: "YuchengHistory", code: 2, userInfo: [NSLocalizedDescriptionKey: "Sport history query failed: \(state)"]))
                }
                if healthDone { finish() }
            }
        }
        YCProduct.queryHealthData(device, dataType: .combinedData) { state, response in
            DispatchQueue.main.async {
                guard !finished && !healthDone else { return }
                healthDone = true
                if state == .noRecord {
                    health = []
                } else if state == .succeed, let rows = response as? [YCHealthDataCombinedData] {
                    let all = rows.map { healthConverter.convert(healthDataFromDevice: $0) }
                    health = all.filter { $0.startTimestamp >= start && $0.startTimestamp <= end }
                    filtered = filtered || health.count != all.count
                } else {
                    errors.append(NSError(domain: "YuchengHistory", code: 2, userInfo: [NSLocalizedDescriptionKey: "Health history query failed: \(state)"]))
                }
                if sportDone { finish() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + YuchengCore.TIME_TO_TIMEOUT) {
            guard !finished else { return }
            onHealth?(YuchengHealthTimeOutEvent(isTimeout: true))
            finish()
        }
        return completer.future.handleEvents(receiveCancel: {
            DispatchQueue.main.async { finish(cancelled: true) }
        }).eraseToAnyPublisher()
    }

    func otaUpdate(device: CBPeripheral, path: String, onUpdate: UpdateHandler?, completion: @escaping (Result<Bool, any Error>) -> Void) {
        YCProduct.jlDeviceUpgradeFirmware(device, filePath: path) { state, progress, didSend in
            print("UPGRADE PROGRESS = " + String(progress))
            print("UPGRADE DID SEND = " + didSend.description)
            DispatchQueue.main.async {
                onUpdate?(YuchengUpdateProgressEvent(progress: Double(progress)))
            }
            switch (state) {
            case .start:
                print("UPGRADE START")
                DispatchQueue.main.async {
                    let timeStamp = Int64(Date().timeIntervalSince1970).toMilliseconds()
                    onUpdate?(YuchengUpdateStartEvent(startTimestamp: timeStamp))
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
                self.reconnectWithMacAddr(onUpdate: onUpdate, completion: completion)
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
                        onUpdate?(YuchengUpdateCompleteEvent(completeTimestamp: timeStamp))
                    }
                }
                break
            case .failed:
                print("UPGRADE FAILED")
                if (!self.isUpgradeCompleted) {
                    completion(.failure(UpgradeFirmwareError.failed("Failed to upgrade!")))
                    DispatchQueue.main.async {
                        onUpdate?(YuchengUpdateErrorEvent(error: "Failed to upgrade!"))
                    }
                    self.isUpgradeCompleted = true
                }
                break
            @unknown default:
                print ("UPGRADE UNKNOWN")
                if (!self.isUpgradeCompleted) {
                    completion(.failure(UpgradeFirmwareError.failed("Unknown state")))
                    DispatchQueue.main.async {
                        onUpdate?(YuchengUpdateErrorEvent(error: "Failed to upgrade!"))
                    }
                    self.isUpgradeCompleted = true
                }
                break
            }
        }
    }
    /// Connecting devices back
    func reconnectWithMacAddr(onUpdate: UpdateHandler?, completion: @escaping (Result<Bool, any Error>) -> Void) {
        usleep(3_500_000)
        repeatScanJLCount = 0
        scanJLForceOtaDevice(onUpdate: onUpdate, completion: completion)
    }
    /// scan devices
    private func scanJLForceOtaDevice(onUpdate: UpdateHandler?, completion: @escaping (Result<Bool, any Error>) -> Void) {
        repeatScanJLCount += 1
        if repeatScanJLCount >= YuchengCore.REPEAT_SCAN_JL_FORCE_OTA_COUNT {
            return
        }
        // Search Device
        YCProduct.scanningDevice(delayTime: 6.0) { devices, error in
            if (devices.isEmpty) {
                YuchengCore.shared.currentDevice = YCProduct.shared.currentPeripheral
                if YuchengCore.shared.currentDevice != nil {
                    self.connectForceOtaDevice(onUpdate: onUpdate, completion: completion)
                }
            }
            for device in devices {
                if (!self.scannedDevicesToUpdate.contains(device)) {
                    print("Device found, try connect force ota device: \(device.macAddress)")
                    self.scannedDevicesToUpdate.append(device)
                    self.connectForceOtaDevice(onUpdate: onUpdate, completion: completion)
                }
            }
        }
    }
    /// Reconnect equipment
    private func connectForceOtaDevice(onUpdate: UpdateHandler?, completion: @escaping (Result<Bool, any Error>) -> Void) {
        if (self.scannedDevicesToUpdate.isEmpty && YuchengCore.shared.currentDevice != nil) {
            let device = YuchengCore.shared.currentDevice!
            print("Device mac : Reconnect mac = " + device.macAddress.uppercased() + " : " + YuchengCore.shared.reconnectMacAddress.uppercased())
            if device.macAddress.uppercased() == YuchengCore.shared.reconnectMacAddress.uppercased() {
                YCProduct.connectDevice(device) { [weak self] state, error
                    in
                    print(state)
                    if (error != nil) {
                        print(error!)
                    }
                    if state == .connected {
                        self?.otaUpdate(device: device, path: self?.filePathToUpdate ?? "", onUpdate: onUpdate, completion: completion)
                    } else {
                        self?.scanJLForceOtaDevice(onUpdate: onUpdate, completion: completion)
                    }
                }
                return
            }
        } else {
            for device in scannedDevicesToUpdate {
                print("Device mac : Reconnect mac = " + device.macAddress.uppercased() + " : " + YuchengCore.shared.reconnectMacAddress.uppercased())
                if device.macAddress.uppercased() == YuchengCore.shared.reconnectMacAddress.uppercased() {
                    YCProduct.connectDevice(device) { [weak self] state, error
                        in
                        print(state)
                        if (error != nil) {
                            print(error!)
                        }
                        if state == .connected {
                            self?.otaUpdate(device: device, path: self?.filePathToUpdate ?? "", onUpdate: onUpdate, completion: completion)
                        } else {
                            self?.scanJLForceOtaDevice(onUpdate: onUpdate, completion: completion)
                        }
                    }
                    return
                }
            }
        }
        scanJLForceOtaDevice(onUpdate: onUpdate, completion: completion)
    }
    
    func isConnected() -> Bool {
        let isConn = ringState == .connected || ringState == .readWriteOK
        print("isConnected() = \(isConn)")
        return isConn
    }
}
