import Flutter
import UIKit
import CoreBluetooth
import YCProductSDK

private class YuchengHostApiImpl : YuchengHostApi {
    private let onDevice: (_: YuchengDeviceEvent) -> Void;
    private let onSleepData: (_: YuchengSleepEvent) -> Void;
    private let onState: (_: YuchengProductStateEvent) -> Void;
    private var scannedDevices: [CBPeripheral] = [];
    private var currentDevice: CBPeripheral? = nil;
    private var sleepData: [YuchengSleepDataEvent] = [];
    private var index: Int = 0;
    
    init(onDevice: @escaping (_: YuchengDeviceEvent) -> Void, onSleepData: @escaping (_: YuchengSleepEvent) -> Void, onState: @escaping (_: YuchengProductStateEvent) -> Void) {
        self.onDevice = onDevice
        self.onSleepData = onSleepData
        self.onState = onState
        initApi()
    }
    
    func initApi() {
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
            onState(YuchengProductStateDataEvent(state: YuchengProductState.connected))
            currentDevice = YCProduct.shared.currentPeripheral
        } else if (state == YCProductState.connectedFailed) {
            onState(YuchengProductStateDataEvent(state: YuchengProductState.connectedFailed))
        } else if (state == YCProductState.disconnected) {
            onState(YuchengProductStateDataEvent(state: YuchengProductState.disconnected))
        } else if (state == YCProductState.unavailable) {
            onState(YuchengProductStateDataEvent(state: YuchengProductState.unavailable))
        } else if (state == YCProductState.timeout) {
            onState(YuchengProductStateDataEvent(state: YuchengProductState.timeOut))
        } else {
            onState(YuchengProductStateDataEvent(state: YuchengProductState.unknown))
        }
    }
    
    func startScanDevices(scanTimeInSeconds: Double?) throws {
        var isCompleted = false
        YCProduct.scanningDevice(delayTime: scanTimeInSeconds ?? 3.0) { devices, error in
            if (error != nil) {
                self.onDevice(YuchengDeviceCompleteEvent(completed: false))
                isCompleted = true;
            } else {
                self.scannedDevices = devices;
                for device in devices {
                    var lastConnectedDevice = YCProduct.shared.currentPeripheral;
                    var isCurrentDevice = lastConnectedDevice?.macAddress == device.macAddress;
                    self.currentDevice = isCurrentDevice ? device : nil;
                    self.onDevice(YuchengDeviceDataEvent(index: Int64(self.index), mac: device.macAddress, isCurrentConnected: isCurrentDevice, deviceName: device.name ?? device.deviceModel))
                    self.index += 1
                }
                self.onDevice(YuchengDeviceCompleteEvent(completed: true))
                isCompleted = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if (isCompleted) {
                return;
            }
            self.onDevice(YuchengDeviceCompleteEvent(completed: true))
        }
    }
    
    func isDeviceConnected(device: YuchengDevice, completion: @escaping (Result<Bool, any Error>) -> Void)
    {
        do {
            var lastConnectedDevice = YCProduct.shared.currentPeripheral;
            var isConnected = device.isCurrentConnected && (lastConnectedDevice?.macAddress == device.uuid);
            completion(.success(isConnected))
        } catch (let e) {
            completion(.failure(e))
        }
    }
    
    func connect(device: YuchengDevice?, completion: @escaping (Result<Bool, any Error>) -> Void) {
        if (device == nil) {
            completion(.success(false));
            return;
        }
        if (currentDevice != nil) {
            if (device?.deviceName == currentDevice?.name || device?.uuid == currentDevice?.macAddress) {
                completion(.success(true))
                return;
            }
        }
        
        currentDevice = scannedDevices.first(where: { scannedDevice in
            scannedDevice.name == device?.deviceName || scannedDevice.macAddress == device?.uuid
        })
        
        if (currentDevice == nil) {
            currentDevice = YCProduct.shared.currentPeripheral;
        }
        if (currentDevice == nil) {
            completion(.success(false))
            return;
        }
        
        var isCompleted = false;
        YCProduct.connectDevice(currentDevice!) { state, error in
            if let error = error {
                isCompleted = true
                completion(.failure(error));
            } else {
                if state == .connected {
                    isCompleted = true
                    completion(.success(true));
                    self.querySleepData({result in
                        print(result)
                    }, {})
                } else {
                    isCompleted = true
                    completion(.success(false))
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if (isCompleted) {
                return;
            }
            completion(.success(false))
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
            var device = YCProduct.shared.currentPeripheral ?? currentDevice
            if device == nil {
                completion(.success(nil))
                return
            }
            var isCurrentDevice = device!.macAddress == currentDevice?.macAddress;
            completion(.success(YuchengDevice(index: 0, deviceName: device!.name ?? device!.deviceModel, uuid: device!.macAddress, isCurrentConnected: isCurrentDevice)))
        } catch (let e) {
            completion(.failure(e))
        }
    }
    
    private func querySleepData(_ completion: @escaping (Result<[(any YuchengSleepEvent)?], any Error>) -> Void, _ complete: @escaping () -> Void) {
        YCProduct.queryHealthData(dataType: YCQueryHealthDataType.sleep) { state, response in
            if state == .succeed, let datas = response as? [YCHealthDataSleep] {
                for info in datas {
                    print(info.startTimeStamp,
                          info.endTimeStamp,
                          info.lightSleepCount,
                          info.lightSleepMinutes,
                          info.deepSleepCount,
                          info.deepSleepMinutes,
                          info.sleepDetailDatas
                    )
                    var sleepDetails: [YuchengSleepDataDetail] = []
                    var minutes: YuchengSleepDataMinutes? = nil
                    var seconds: YuchengSleepDataSeconds? = nil
                    
                    for detail in info.sleepDetailDatas {
                        var type = YuchengSleepType.unknown
                        let detailType = detail.sleepType
                        if (detailType == YCHealthDataSleepType.awake) {
                            type = .awake
                        } else if (detailType == YCHealthDataSleepType.deepSleep) {
                            type = .deep
                        } else if (detailType == YCHealthDataSleepType.lightSleep) {
                            type = .light
                        } else if (detailType == YCHealthDataSleepType.unknow) {
                            type = .unknown
                        } else if (detailType == YCHealthDataSleepType.rem) {
                            type = .rem
                        }
                        sleepDetails.append(YuchengSleepDataDetail(startTimeStamp: Int64(detail.startTimeStamp), duration: Int64(detail.duration), type: type))
                    }
                    if (info.deepSleepCount == 0xFFFF) {
                        seconds = YuchengSleepDataSeconds(deepSleepSeconds: Int64(info.deepSleepSeconds), remSleepSeconds: Int64(info.remSleepSeconds), lightSleepSeconds: Int64(info.lightSleepSeconds))
                    } else {
                        minutes = YuchengSleepDataMinutes(deepSleepMinutes: Int64(info.deepSleepMinutes), remSleepMinutes: Int64(info.remSleepMinutes), lightSleepMinutes: Int64(info.lightSleepMinutes))
                    }
                    let event = YuchengSleepDataEvent(startTimeStamp: Int64(info.startTimeStamp), endTimeStamp: Int64(info.endTimeStamp), deepSleepCount: Int64(info.deepSleepCount), lightSleepCount: Int64(info.lightSleepCount), minutes: minutes, seconds: seconds, details: sleepDetails)
                    self.onSleepData(event)
                    self.sleepData.append(event)
                }
                completion(.success(self.sleepData))
                self.sleepData = []
                complete()
            } else {
                completion(.success([]))
                print("No data")
                complete()
            }
        }
    }
    
    func getSleepData(completion: @escaping (Result<[(any YuchengSleepEvent)?], any Error>) -> Void) {
        do {
            var isCompleted = false
            querySleepData(completion, {
                isCompleted = true
            })
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                if (isCompleted) {
                    return
                }
                completion(.success([]))
            }
        } catch (let e) {
            completion(.failure(e))
        }
    }
}

private class DeviceStateStreamHandlerImpl : DeviceStateStreamHandler {
    private var eventSink: PigeonEventSink<YuchengProductStateEvent>? = nil;
    
    override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<any YuchengProductStateEvent>) {
        eventSink = sink;
    }
    override func onCancel(withArguments arguments: Any?) {
        eventSink = nil;
    }
    
    func onDeviceStateChanged(_ event: YuchengProductStateEvent) {
        eventSink?.success(event);
    }
    
    func detach() {
        eventSink?.endOfStream()
        eventSink = nil;
    }
}

private class DeviceStreamHandlerImpl : DevicesStreamHandler {
    private var eventSink: PigeonEventSink<YuchengDeviceEvent>? = nil;
    
    override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<any YuchengDeviceEvent>) {
        eventSink = sink;
    }
    
    override func onCancel(withArguments arguments: Any?) {
        eventSink = nil;
    }
    
    func onDeviceChanged(_ event: YuchengDeviceEvent) {
        eventSink?.success(event);
    }
    
    func detach() {
        eventSink?.endOfStream()
        eventSink = nil;
    }
}

private class SleepDataHandlerImpl : SleepDataStreamHandler {
    private var eventSink: PigeonEventSink<YuchengSleepEvent>? = nil;
    
    
    override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<YuchengSleepEvent>) {
        eventSink = sink;
    }
    
    override func onCancel(withArguments arguments: Any?) {
        eventSink = nil;
    }
    
    func onSleepDataChanged(_ event: YuchengSleepEvent) {
        eventSink?.success(event);
    }
    
    func detach() {
        eventSink?.endOfStream()
        eventSink = nil;
    }
}


public class YuchengBlePlugin: NSObject, FlutterPlugin {
    private static var api: YuchengHostApi? = nil
    private static var devicesHandler: DeviceStreamHandlerImpl? = nil
    private static var sleepDataHandler: SleepDataHandlerImpl? = nil
    private static var deviceStateStreamHandler: DeviceStateStreamHandlerImpl? = nil
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        devicesHandler = DeviceStreamHandlerImpl();
        sleepDataHandler = SleepDataHandlerImpl();
        deviceStateStreamHandler = DeviceStateStreamHandlerImpl();
        
        _ = YCProduct.shared;
        
        DevicesStreamHandler.register(with: registrar.messenger(), streamHandler: devicesHandler!)
        SleepDataStreamHandler.register(with: registrar.messenger(), streamHandler: sleepDataHandler!)
        DeviceStateStreamHandler.register(with: registrar.messenger(), streamHandler: deviceStateStreamHandler!)
        
        api = YuchengHostApiImpl(onDevice: { event in
            devicesHandler?.onDeviceChanged(event)
        }, onSleepData: { event in
            sleepDataHandler?.onSleepDataChanged(event)
        }, onState: { event in
            deviceStateStreamHandler?.onDeviceStateChanged(event)
        })
        
        YuchengHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: api!)
    }
    
    public func detachFromEngine(for registrar: any FlutterPluginRegistrar) {
        YuchengHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
        YCProduct.stopSearchDevice()
        YuchengBlePlugin.devicesHandler?.detach()
        YuchengBlePlugin.sleepDataHandler?.detach()
        YuchengBlePlugin.deviceStateStreamHandler?.detach()
    }
}
