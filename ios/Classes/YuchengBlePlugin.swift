import Flutter
import UIKit
import CoreBluetooth
import YCProductSDK

private class YuchengHostApiImpl : YuchengHostApi {
    private var onDevice: (_: YuchengDeviceEvent) -> Unit;
    private var onSleepData: (_: YuchengSleepEvent) -> Unit;
    private var onState: (_: YuchengProductStateEvent) -> Unit;
    private var scannedDevices: [CBPeripheral] = [];
    private var currentDevice: CBPeripheral? = nil;
    private var sleepData: [YuchengSleepDataEvent] = [];
    
    init(onDevice: @escaping (_: YuchengDeviceEvent) -> Unit, onSleepData: @escaping (_: YuchengSleepEvent) -> Unit, onState: @escaping (_: YuchengProductStateEvent) -> Unit) {
        self.onDevice = onDevice
        self.onSleepData = onSleepData
        self.onState = onState
        initApi()
    }
    
    func initApi() throws {
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
        YCProduct.scanningDevice(delayTime: 3.0) { devices, error in
            if (error != null) {
                onDevice(YuchengSleepErrorEvent(error: error.localizedDescription))
            } else {
                scannedDevices = devices;
                for device in devices {
                    var lastConnectedDevice = YCProduct.currentPeripheral;
                    var isCurrentDevice = lastConnectedDevice?.identifier.uuid == device.identifier.uuid;
                    currentDevice = isCurrentDevice ? device : nil;
                    onDevice(YuchengDeviceDataEvent(index: 0, mac: device.macAddress, deviceName: device.name, isCurrentConnected: isCurrentDevice))
                }
            }
        }
    }
    
    func isDeviceConnected(device: YuchengDevice, completion: @escaping (Result<Bool, any Error>) -> Void)
    {
        do {
            var lastConnectedDevice = YCProduct.currentPeripheral;
            var isConnected = device.isCurrentConnected ?? (lastConnectedDevice?.identifier.uuid == device.uuid);
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
        YCProduct.connectDevice(currentDevice: currentDevice) { state, error in
            if let error = error {
                completion(.failure(error));
            } else {
                if state == .connected {
                    completion(.success(true));
                } else {
                    completion(.success(false))
                }
            }
        }
    }
    
    func disconnect(completion: @escaping (Result<Void, any Error>) -> Void) {
        YCProduct.disconnectDevice(currentDevice ?? YCProduct.shared.currentPeripheral) { state, error in
            if let error = error {
                completion(.failure(error));
            } else {
                completion(.success(()))
            }
        }
    }
    
    func getCurrentConnectedDevice(completion: @escaping (Result<YuchengDevice?, any Error>) -> Void) {
        do {
            var device = YCProduct.shared.currentPeripheral ?? currentDevice
            completion(.success(device))
        } catch (let e) {
            completion(.failure(e))
        }
    }
    
    func getSleepData(completion: @escaping (Result<[(any YuchengSleepEvent)?], any Error>) -> Void) {
        do {
            YCProduct.queryHealthData(datatType: YCQueryHealthDataType.sleep) { state, response in
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
                        let sleepDetails: [YuchengSleepDataDetail] = []
                        var minutes: YuchengSleepDataMinutes? = nil
                        var seconds: YuchengSleepDataSeconds? = nil
                        
                        for detail in info.details {
                            let type = YuchengSleepType.unknown
                            let detailType = detail.type
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
                            sleepDetails.append(YuchengSleepDataDetail(startTimeStamp: detail.startTimeStamp, duration: detail.duration, type: type))
                        }
                        if (info.deepSleepCount == 0xFFFF) {
                            seconds = YuchengSleepDataSeconds(deepSleepSeconds: info.deepSleepSeconds, remSleepSeconds: info.remSleepSeconds, lightSleepSeconds: info.lightSleepSeconds)
                        } else {
                            minutes = YuchengSleepDataMinutes(deepSleepMinutes: info.deepSleepMinutes, remSleepMinutes: info.remSleepMinutes, lightSleepMinutes: info.lightSleepMinutes)
                        }
                        let event = YuchengSleepDataEvent(startTimeStamp: info.startTimeStamp, endTimeStamp: info.endTimeStamp, deepSleepCount: info.deepSleepCount, lightSleepCount: info.lightSleepCount, details: sleepDetails, minutes: minutes, seconds: seconds)
                        onSleepData(event)
                        sleepData.append(event)
                    }
                    completion(.success(sleepData))
                    sleepData = []
                } else {
                    print("No data")
                }
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
    
    func onDetach() {
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
    
    func onDetach() {
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
    
    func onSleepDataChanged(_ event: YuchengSleepDataEvent) {
        eventSink?.success(event);
    }
    
    func onDetach() {
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
        
        api = YuchengHostApiImpl(onDevice: devicesHandler?.onDeviceChanged, onSleepData: sleepDataHandler?.onSleepDataChanged, onDeviceState: deviceStateStreamHandler?.onDeviceStateChanged)
        
        YuchengHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: api!)
    }
    
    public func detachFromEngine(for registrar: any FlutterPluginRegistrar) {
        YuchengHostApiSetup.setUp(binding.binaryMessenger, null)
        YCProduct.shared.stopSearchDevice()
        devicesHandler?.detach()
        sleepDataHandler?.detach()
        deviceStateStreamHandler?.detach()
    }
}
