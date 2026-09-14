import Foundation
import Combine

var scenario = CommandLine.arguments[1]
struct NoConnectionException: Error {}
struct Device { var macAddress = ""; var name = "" }
enum YCProductState { case succeed, failed, noRecord, timeout }
enum YCDeleteHealthDataType { case sleep, step, combinedData }
enum YCQueryHealthDataType: Hashable { case sleep, step, combinedData }
struct YCHealthDataSleep {}
struct YCHealthDataStep {}
struct YCHealthDataCombinedData {}
struct YuchengSleepData { var startTimeStamp: Int64 = 10; var endTimeStamp: Int64 = 20 }
struct YuchengSportData { var startTimeStamp: Int64 = 10; var endTimeStamp: Int64 = 20 }
struct YuchengHealthData { var startTimestamp: Int64 = 10 }
struct YuchengHealthSportData { var healthData: [YuchengHealthData]; var sportData: [YuchengSportData] }
class YuchengSleepDataConverter { func convert(sleepDataFromDevice: YCHealthDataSleep) -> YuchengSleepData { YuchengSleepData() } }
class YuchengSportDataConverter { func convert(sportDataFromDevice: YCHealthDataStep) -> YuchengSportData { YuchengSportData() } }
class YuchengHealthDataConverter { func convert(healthDataFromDevice: YCHealthDataCombinedData) -> YuchengHealthData { YuchengHealthData() } }
protocol SleepEvent {}
protocol HealthEvent {}
struct YuchengSleepErrorEvent: SleepEvent { let error: String }
struct YuchengSleepDataEvent: SleepEvent { let sleepData: YuchengSleepData }
struct YuchengSleepTimeOutEvent: SleepEvent { let isTimeout: Bool }
struct YuchengHealthErrorEvent: HealthEvent { let error: String }
struct YuchengHealthDataEvent: HealthEvent { let healthData: YuchengHealthSportData }
struct YuchengHealthTimeOutEvent: HealthEvent { let isTimeout: Bool }
typealias SleepHandler = (SleepEvent) -> Void
typealias HealthHandler = (HealthEvent) -> Void

class YCProduct {
    static var deleteCalls = 0
    static func deleteHealthData(_ device: Device?, dataType: YCDeleteHealthDataType,
                                 completion: @escaping (YCProductState, Any?) -> Void) {
        deleteCalls += 1
        DispatchQueue.main.async { completion(.succeed, nil); completion(.succeed, nil) }
    }
    static let shared = YCProduct()
    var currentPeripheral: Device? = Device()
    static func queryHealthData(_ device: Device?, dataType: YCQueryHealthDataType,
                                completion: @escaping (YCProductState, Any?) -> Void) {
        let data: Any = dataType == .sleep ? [YCHealthDataSleep()] as Any :
            dataType == .step ? [YCHealthDataStep()] as Any : [YCHealthDataCombinedData()] as Any
        let empty: Any = dataType == .sleep ? [YCHealthDataSleep]() as Any :
            dataType == .step ? [YCHealthDataStep]() as Any : [YCHealthDataCombinedData]() as Any
        var state = YCProductState.succeed
        var response: Any? = data
        var delay = 0.005
        if scenario.hasSuffix("_timeout") && !scenario.contains("partial") { return }
        if scenario.hasSuffix("_error") && !scenario.contains("partial") && scenario != "health_empty_error" { state = .failed; response = nil }
        if scenario.hasSuffix("_empty") { response = empty }
        if scenario.hasSuffix("_no_record") { state = .noRecord; response = nil }
        if scenario == "health_empty_error" { state = dataType == .step ? .failed : .succeed; response = dataType == .step ? nil : empty }
        if scenario.hasPrefix("health_partial") && dataType == .step || scenario.hasPrefix("sport_partial") && dataType == .combinedData {
            if scenario.hasSuffix("timeout") { return }
            state = .failed; response = nil
        }
        if scenario.hasSuffix("_late") { delay = 0.07 }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { completion(state, response) }
        if scenario.hasSuffix("_duplicate") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) { completion(state, response) }
        }
    }
}

var values = 0
var failures = 0
var completions = 0
var dataEvents = 0
var timeoutEvents = 0
var receivedSleep = -1
var receivedHealth = -1
var receivedSport = -1
var subscription: AnyCancellable?
let invalid = scenario.hasSuffix("_invalid")
if scenario.hasPrefix("sleep") {
    subscription = YuchengCore.shared.getSleepData(startTimestamp: invalid ? 100 : 0, endTimestamp: 100,
        sleepConverter: YuchengSleepDataConverter(), onSleepData: { event in
            if event is YuchengSleepDataEvent { dataEvents += 1 }
            if event is YuchengSleepTimeOutEvent { timeoutEvents += 1 }
        }).sink(receiveCompletion: { completion in
            completions += 1
            if case .failure = completion { failures += 1 }
        }, receiveValue: { value in values += 1; receivedSleep = value.count })
} else {
    subscription = YuchengCore.shared.getHealthData(startTimestamp: invalid ? 100 : 0, endTimestamp: 100,
        sportConverter: YuchengSportDataConverter(), healthConverter: YuchengHealthDataConverter(),
        onHealth: { event in
            if event is YuchengHealthDataEvent { dataEvents += 1 }
            if event is YuchengHealthTimeOutEvent { timeoutEvents += 1 }
        }).sink(receiveCompletion: { completion in
            completions += 1
            if case .failure = completion { failures += 1 }
        }, receiveValue: { value in
            values += 1; receivedHealth = value.healthData.count; receivedSport = value.sportData.count
        })
}
if scenario.hasSuffix("_cancel") {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { subscription?.cancel() }
}
var earlyDeleteResult: Bool?
let earlyReply: (Result<Bool, Error>) -> Void = { earlyDeleteResult = try? $0.get() }
// Before pumping the main queue, no SDK callback can have completed this read.
if scenario.hasPrefix("sleep") { HistoryHost().deleteSleepData(completion: earlyReply) }
else { HistoryHost().deleteHealthSportData(completion: earlyReply) }
RunLoop.main.run(until: Date().addingTimeInterval(0.12))
func require(_ condition: Bool, _ message: String) {
    if !condition { print("FAIL: \(message); values=\(values), failures=\(failures), completions=\(completions), events=\(dataEvents), timeouts=\(timeoutEvents)"); exit(1) }
}
require(earlyDeleteResult == false && YCProduct.deleteCalls == 0, "active read blocks automatic SDK delete")
if scenario.hasSuffix("_cancel") {
    require(values == 0 && completions == 0 && dataEvents == 0 && timeoutEvents == 0, "cancel suppresses late results/events")
} else if (scenario.hasSuffix("_error") || scenario.hasSuffix("_timeout") || scenario.hasSuffix("_late") || invalid) && !scenario.contains("partial") {
    require(failures == 1 && completions == 1 && values == 0 && dataEvents == 0, "terminal error, no false empty/data")
} else {
    require(values == 1 && completions == 1 && failures == 0, "one success")
    let empty = scenario.hasSuffix("_empty") || scenario.hasSuffix("_no_record")
    if scenario.hasPrefix("sleep") {
        require(receivedSleep == (empty ? 0 : 1) && dataEvents == (empty ? 0 : 1), "sleep snapshot once")
    } else {
        require(receivedHealth == (empty || scenario.hasPrefix("sport_partial") ? 0 : 1), "health retained")
        require(receivedSport == (empty || scenario.hasPrefix("health_partial") ? 0 : 1), "sport retained")
        require(dataEvents == 1, "health event once")
    }
}

// Model HTTP ack followed by the actual automatic-delete methods. Incomplete
// and cancelled reads must retain SDK history, even after a later full read.
let originalScenario = scenario
if scenario.contains("partial") {
    scenario = "health_success"
    subscription = YuchengCore.shared.getHealthData(startTimestamp: 0, endTimestamp: 100,
        sportConverter: YuchengSportDataConverter(), healthConverter: YuchengHealthDataConverter())
        .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
}
var deleteResults = 0
var deleted: Bool?
let onDelete: (Result<Bool, Error>) -> Void = { result in
    deleteResults += 1
    deleted = try? result.get()
}
if originalScenario.hasPrefix("sleep") { HistoryHost().deleteSleepData(completion: onDelete) }
else { HistoryHost().deleteHealthSportData(completion: onDelete) }
RunLoop.main.run(until: Date().addingTimeInterval(0.06))
let safe = !originalScenario.contains("partial") && !originalScenario.hasSuffix("_error") && !originalScenario.hasSuffix("_timeout") && !originalScenario.hasSuffix("_late") && !originalScenario.hasSuffix("_cancel") && !invalid
require(deleteResults == 1 && deleted == safe, "delete reply once, only after complete history")
require(YCProduct.deleteCalls == (safe ? (originalScenario.hasPrefix("sleep") ? 1 : 2) : 0), "unsafe ack must not call SDK delete")
