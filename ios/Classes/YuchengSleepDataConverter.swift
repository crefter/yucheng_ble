//
//  YuchengSleepDataConverter.swift
//  Pods
//
//  Created by Maxim Zarechnev on 10.04.2025.
//

import YCProductSDK

final class YuchengSleepDataConverter: Sendable {
    func convert(sleepDataFromDevice: YCHealthDataSleep) -> YuchengSleepData {
        var sleepDetails: [YuchengSleepDataDetail] = []
        var awakeCount = 0;
        var awakeSeconds = 0;
        for detail in sleepDataFromDevice.sleepDetailDatas {
            var type = YuchengSleepType.unknown
            let detailType = detail.sleepType
            if (detailType == YCHealthDataSleepType.awake) {
                type = .awake
                awakeCount += 1
                awakeSeconds += Int(detail.duration)
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
        let isOldFormat = sleepDataFromDevice.deepSleepCount != 0xFFFF;
        
        let deepSeconds = isOldFormat ? sleepDataFromDevice.deepSleepMinutes * 60 : sleepDataFromDevice.deepSleepSeconds
        let lightSeconds = isOldFormat ? sleepDataFromDevice.lightSleepMinutes * 60 : sleepDataFromDevice.lightSleepSeconds
        let remSeconds = isOldFormat ? sleepDataFromDevice.remSleepMinutes * 60 : sleepDataFromDevice.remSleepSeconds
        
        let event = YuchengSleepData(startTimeStamp: Int64(sleepDataFromDevice.startTimeStamp).toMilliseconds(), endTimeStamp: Int64(sleepDataFromDevice.endTimeStamp).toMilliseconds(), deepCount: Int64(sleepDataFromDevice.deepSleepCount), lightCount: Int64(sleepDataFromDevice.lightSleepCount),  awakeCount: Int64(awakeCount), deepInSeconds: Int64(deepSeconds), remInSeconds: Int64(remSeconds), lightInSeconds: Int64(lightSeconds), awakeInSeconds: Int64(awakeSeconds), details: sleepDetails )
        return event
    }
}
