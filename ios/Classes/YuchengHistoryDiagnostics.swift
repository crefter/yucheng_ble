import Foundation
import YCProductSDK

enum YuchengHistoryDiagnostics {
    static func callback(_ category: String, state: YCProductState, count: Int?) {
        let outcome: String
        switch state {
        case .noRecord: outcome = "no_record"
        case .succeed: outcome = count == nil ? "missing_payload" : "success"
        default: outcome = "sdk_error"
        }
        YuchengDiagnostics.shared.summary("history_callback",
            "category=\(category) outcome=\(outcome) sdk_state=\(state.rawValue) rows=\(count ?? -1)")
    }

    static func sleep(_ rows: [YCHealthDataSleep], session: Int?) {
        YuchengDiagnostics.shared.detailed("history_sleep_payload", session: session, chunkSize: 1, rows: rows.suffix(16).map {
            [
                "startTimeStamp": $0.startTimeStamp,
                "endTimeStamp": $0.endTimeStamp,
                "deepSleepCount": $0.deepSleepCount,
                "lightSleepCount": $0.lightSleepCount,
                "deepSleepMinutes": $0.deepSleepMinutes,
                "lightSleepMinutes": $0.lightSleepMinutes,
                "remSleepMinutes": $0.remSleepMinutes,
                "deepSleepSeconds": $0.deepSleepSeconds,
                "lightSleepSeconds": $0.lightSleepSeconds,
                "remSleepSeconds": $0.remSleepSeconds,
                "stage_count": $0.sleepDetailDatas.count,
                "stages": $0.sleepDetailDatas.suffix(1024).map { stage in
                    [
                        "startTimeStamp": stage.startTimeStamp,
                        "duration": stage.duration,
                        "sleepType": stage.sleepType.rawValue
                    ]
                }
            ]
        })
    }

    static func health(_ rows: [YCHealthDataCombinedData], session: Int?) {
        YuchengDiagnostics.shared.detailed("history_health_payload", session: session, rows: rows.suffix(2048).map {
            [
                "startTimeStamp": $0.startTimeStamp,
                "heartRate": $0.heartRate,
                "hrv": $0.hrv,
                "cvrr": $0.cvrr,
                "bloodOxygen": $0.bloodOxygen,
                "systolicBloodPressure": $0.systolicBloodPressure,
                "diastolicBloodPressure": $0.diastolicBloodPressure,
                "respirationRate": $0.respirationRate,
                "step": $0.step,
                "temperature": $0.temperature.isFinite ? $0.temperature as Any : NSNull()
            ]
        })
    }

    static func sport(_ rows: [YCHealthDataStep], session: Int?) {
        YuchengDiagnostics.shared.detailed("history_sport_payload", session: session, rows: rows.suffix(2048).map {
            [
                "startTimeStamp": $0.startTimeStamp,
                "endTimeStamp": $0.endTimeStamp,
                "step": $0.step,
                "calories": $0.calories,
                "distance": $0.distance
            ]
        })
    }
}
