import Flutter
import UIKit
import CoreBluetooth
import YCProductSDK

enum UnimplementedError : Error {
    case notImplemented(String)
}

private class YuchengHostApiImpl : YuchengHostApi {
    private let onDevice: (_: YuchengDeviceEvent) -> Void;
    private let onSleepData: (_: YuchengSleepEvent) -> Void;
    private let onState: (_: YuchengDeviceStateEvent) -> Void;
    private let converter: YuchengSleepDataConverter;
    private var scannedDevices: [CBPeripheral] = [];
    private var currentDevice: CBPeripheral? = nil;
    private var sleepData: [YuchengSleepDataEvent] = [];
    private var index: Int = 0;
    
    init(onDevice: @escaping (_: YuchengDeviceEvent) -> Void, onSleepData: @escaping (_: YuchengSleepEvent) -> Void, onState: @escaping (_: YuchengDeviceStateEvent) -> Void, converter: YuchengSleepDataConverter) {
        self.onDevice = onDevice
        self.onSleepData = onSleepData
        self.onState = onState
        self.converter = converter
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
            onState(YuchengDeviceStateDataEvent(state: YuchengProductState.connected))
        } else if (state == YCProductState.connectedFailed) {
            onState(YuchengDeviceStateDataEvent(state: YuchengProductState.connectedFailed))
        } else if (state == YCProductState.disconnected) {
            onState(YuchengDeviceStateDataEvent(state: YuchengProductState.disconnected))
        } else if (state == YCProductState.unavailable) {
            onState(YuchengDeviceStateDataEvent(state: YuchengProductState.unavailable))
        } else if (state == YCProductState.timeout) {
            onState(YuchengDeviceStateDataEvent(state: YuchengProductState.timeOut))
        } else if (state == YCProductState.succeed) {
            onState(YuchengDeviceStateDataEvent(state: YuchengProductState.readWriteOK))
            currentDevice = YCProduct.shared.currentPeripheral
        }
        else {
            onState(YuchengDeviceStateDataEvent(state: YuchengProductState.unknown))
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
        
        if (currentDevice != nil) {
            if (device.deviceName == currentDevice?.name || device.uuid == currentDevice?.macAddress) {
                completion(.success(true))
                return;
            }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if (isCompleted) {
                return;
            }
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
                    print(info.startTimeStamp,
                          info.endTimeStamp,
                          info.lightSleepCount,
                          info.lightSleepMinutes,
                          info.deepSleepCount,
                          info.deepSleepMinutes,
                          info.sleepDetailDatas
                    )
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
    private var eventSink: PigeonEventSink<YuchengDeviceStateEvent>? = nil;
    
    override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<any YuchengDeviceStateEvent>) {
        eventSink = sink;
    }
    override func onCancel(withArguments arguments: Any?) {
        eventSink = nil;
    }
    
    func onDeviceStateChanged(_ event: YuchengDeviceStateEvent) {
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
    private static let converter = YuchengSleepDataConverter()
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        print("Register 1")
        devicesHandler = DeviceStreamHandlerImpl();
        sleepDataHandler = SleepDataHandlerImpl();
        deviceStateStreamHandler = DeviceStateStreamHandlerImpl();
        
        print("Register 0")
        _ = YCProduct.shared;
        
        print("Register 2")
        
        DevicesStreamHandler.register(with: registrar.messenger(), streamHandler: devicesHandler!)
        SleepDataStreamHandler.register(with: registrar.messenger(), streamHandler: sleepDataHandler!)
        DeviceStateStreamHandler.register(with: registrar.messenger(), streamHandler: deviceStateStreamHandler!)
        
        print("Register 3")
        
        api = YuchengHostApiImpl(onDevice: { event in
            devicesHandler?.onDeviceChanged(event)
        }, onSleepData: { event in
            sleepDataHandler?.onSleepDataChanged(event)
        }, onState: { event in
            deviceStateStreamHandler?.onDeviceStateChanged(event)
        }, converter: converter)
        
        print("Register 4")
        
        YuchengHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: api!)
        print("Register 5")
    }
    
    public func detachFromEngine(for registrar: any FlutterPluginRegistrar) {
        YuchengHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
        YCProduct.stopSearchDevice()
        YuchengBlePlugin.devicesHandler?.detach()
        YuchengBlePlugin.sleepDataHandler?.detach()
        YuchengBlePlugin.deviceStateStreamHandler?.detach()
    }
}
