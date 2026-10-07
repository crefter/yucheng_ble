import Foundation
import Combine
struct YuchengDevice { let index: Int64; let deviceName: String; let uuid: String; let isReconnected: Bool }
protocol YuchengDeviceEvent {}
struct YuchengDeviceDataEvent: YuchengDeviceEvent { let index: Int64; let mac: String; let isReconnected: Bool; let deviceName: String }
struct YuchengDeviceCompleteEvent: YuchengDeviceEvent { let completed: Bool }
struct YuchengDeviceTimeOutEvent: YuchengDeviceEvent { let isTimeout: Bool }
protocol StateEvent {}
enum RingState { case readWriteOK }
struct YuchengDeviceStateDataEvent: StateEvent { let state: RingState }
struct YuchengDeviceStateTimeOutEvent: StateEvent { let isTimeout: Bool }
typealias DeviceHandler = (any YuchengDeviceEvent) -> Void
struct NoDeviceError: Error { static func noDevice(_ message: String) -> Self { Self() } }
class Device {
 var state: SDKState = .connected
 let identifier = UUID()
 let name: String?
 let macAddress: String
 let deviceModel = "ring"
 init(_ mac: String, _ name: String = "Ring-AB") { macAddress = mac; self.name = name }
}
typealias CBPeripheral = Device
typealias YCProductState = SDKState
enum SDKState { case connected, failed, succeed }
class YCProduct {
 static let shared = YCProduct()
 var currentPeripheral: Device?
 static var advertised: [Device] = []
 static var calls: [String] = []
 static var callbackDevice: Device?
 static func scanningDevice(delayTime: Double, completion: ([Device], Error?) -> Void) { completion(advertised, nil) }
 static func connectDevice(_ device: Device, completion: (SDKState, Error?) -> Void) {
  calls.append(device.macAddress)
  shared.currentPeripheral = callbackDevice ?? device
  shared.currentPeripheral?.state = .connected
  YuchengCore.shared.connected = true
  completion(.connected, nil)
 }
 static func queryDeviceMacAddress(_ completion: (SDKState, Any?) -> Void) {
  completion(shared.currentPeripheral?.state == .connected ? .succeed : .failed, shared.currentPeripheral?.macAddress)
 }
 static func queryDeviceMacAddress(_ device: Device?, completion: (SDKState, Any?) -> Void) {
  queryDeviceMacAddress(completion)
 }
 static func isJLDeviceForceOTA() -> Bool { CommandLine.arguments[1] == "reconnect_ota_canonical" }
}
class YuchengCancelableStore {
 static let shared = YuchengCancelableStore()
 var tokens = Set<AnyCancellable>()
 func subscribe<T>(_ publisher: AnyPublisher<T, Error>, _ completion: @escaping (Subscribers.Completion<Error>) -> Void, receiveValue: @escaping (T) -> Void) {
  publisher.sink(receiveCompletion: completion, receiveValue: receiveValue).store(in: &tokens)
 }
}
class YuchengCore {
 static let shared = YuchengCore()
 static let TIME_TO_QUERY_MAC_ADDR = 0
 static let TIME_TO_RECONNECT = 1
 static let TIME_TO_TIMEOUT = 0.1
 static let TIME_TO_SCAN = 0.01
 static let TIME_TO_SCAN_TIMEOUT = 0.015
 var ringState: RingState = .readWriteOK
 var connected = false
 var currentDevice: Device?
 var scannedDevices: [Device] = []
 var index = 0
 var reconnectMacAddress = ""
 var onState: ((any StateEvent) -> Void)?
 func isConnected() -> Bool { connected }
 var otaAddresses: [String] = []
 func connectForceOtaDevice(onUpdate: Int?, completion: (Bool) -> Void) { otaAddresses.append(reconnectMacAddress); completion(false) }
 // PRODUCTION_METHODS
}
class Host {
 // HOST_METHOD
}
let scenario = CommandLine.arguments[1]
let core = YuchengCore.shared
let a = Device("AA:00:00:00:00:AB")
let b = Device("BB:00:00:00:00:AB")
var wanted = b.macAddress
YCProduct.advertised = [a, b]
core.scannedDevices = [a, b]
if scenario == "same_name_wrong_connected" || scenario == "stale_same_name" {
 core.currentDevice = a
 YCProduct.shared.currentPeripheral = a
 core.connected = scenario == "same_name_wrong_connected"
}
if scenario == "external_exact" { core.scannedDevices = [] }
if scenario == "normalized" { wanted = "bb-00-00-00-00-ab" }
if scenario == "missing_id" { wanted = "" }
if scenario == "invalid_id" { wanted = "not-a-mac" }
if scenario == "wrong_callback" { YCProduct.callbackDevice = a }
if scenario == "matching_connected" { core.currentDevice = b; YCProduct.shared.currentPeripheral = b; core.connected = true }
if scenario.hasPrefix("getter_") {
 core.connected = scenario != "getter_offline_candidate"
 core.currentDevice = scenario == "getter_live_no_cache" || scenario == "getter_nil_once" ? nil : a
 YCProduct.shared.currentPeripheral = scenario == "getter_offline_candidate" || scenario == "getter_nil_once" ? nil : b
 var replies = 0
 var got: YuchengDevice?
 Host().getCurrentConnectedDevice { result in replies += 1; got = try? result.get() }
 if scenario == "getter_nil_once" {
  RunLoop.main.run(until: Date().addingTimeInterval(0.08))
  precondition(replies == 1 && got == nil)
  print("PASS", scenario); exit(0)
 }
 if scenario == "getter_offline_candidate" { precondition(got?.isReconnected == false) }
 precondition(replies == 1 && got?.uuid == (scenario == "getter_offline_candidate" ? a.macAddress : b.macAddress))
 print("PASS", scenario)
 exit(0)
}
if scenario.hasPrefix("host_") {
 core.connected = scenario != "host_offline" && scenario != "host_nil_offline"
 YCProduct.shared.currentPeripheral = a
 if scenario == "host_offline" || scenario == "host_nil_offline" { a.state = .failed }
 var calls = 0
 var result: Bool?
 let requested = scenario == "host_nil" || scenario == "host_nil_offline" ? nil : YuchengDevice(index: 1, deviceName: "Ring-AB", uuid: scenario == "host_other_mac" ? b.macAddress : (scenario == "host_offline" ? a.macAddress : "aa00000000ab"), isReconnected: false)
 Host().isDeviceConnected(device: requested) { reply in calls += 1; result = try? reply.get() }
 precondition(calls == 1 && result == (scenario == "host_nil" || scenario == "host_normalized"))
 print("PASS", scenario)
 exit(0)
}
var value: Bool?
var failed = false
var scan: [YuchengDevice] = []
var token: AnyCancellable?
if scenario.hasPrefix("reconnect_") {
 YCProduct.shared.currentPeripheral = scenario == "reconnect_nil" || scenario == "reconnect_cached_nil" ? nil : (scenario == "reconnect_wrong" ? a : b)
 if scenario == "reconnect_cached_nil" { core.currentDevice = b }
 if scenario == "reconnect_offline" || scenario == "reconnect_wrong_callback" || scenario == "reconnect_ota_canonical" { b.state = .failed }
 if scenario == "reconnect_wrong_callback" { YCProduct.callbackDevice = a }
 token = core.reconnect(uuid: "bb00000000ab", reconnectTimeInSeconds: 1).sink(receiveCompletion: { if case .failure = $0 { failed = true } }, receiveValue: { value = $0 })
} else if scenario.hasPrefix("scan_") {
 if scenario == "scan_same_mac" { YCProduct.advertised = [a, Device("aa00000000ab", "Another")] }
 if scenario == "scan_preserves_connected" { core.currentDevice = a; YCProduct.shared.currentPeripheral = a; core.connected = true }
 token = core.scanDevices(scanTimeInSeconds: 0.01).sink(receiveCompletion: { _ in }, receiveValue: { scan = $0 })
} else {
 token = core.connect(device: YuchengDevice(index: 1, deviceName: "Ring-AB", uuid: wanted, isReconnected: false), connectTimeInSeconds: 6).sink(receiveCompletion: { if case .failure = $0 { failed = true } }, receiveValue: { value = $0 })
}
RunLoop.main.run(until: Date().addingTimeInterval(0.08))
switch scenario {
case "reconnect_wrong", "reconnect_nil": precondition(value == false && YCProduct.calls.isEmpty)
case "reconnect_wrong_callback": precondition(value == false)
case "reconnect_ota_canonical": precondition(value == true && core.otaAddresses == [b.macAddress, b.macAddress])
case "reconnect_normalized", "reconnect_offline", "reconnect_cached_nil": precondition(value == true)
case "scan_distinct_mac": precondition(scan.count == 2)
case "scan_same_mac": precondition(scan.count == 1)
case "scan_preserves_connected": precondition(core.currentDevice === a)
case "missing_id", "invalid_id": precondition(failed && YCProduct.calls.isEmpty)
case "wrong_callback": precondition(value != true && failed)
case "matching_connected": precondition(value == true && YCProduct.calls.isEmpty)
default: precondition(value == true && YCProduct.calls == [b.macAddress])
}
print("PASS", scenario)
