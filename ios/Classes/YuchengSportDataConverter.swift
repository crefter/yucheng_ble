//
//  YuchengSportDataConverter.swift
//  Pods
//
//  Created by Maxim Zarechnev on 18.08.2025.
//

import YCProductSDK

final class YuchengSportDataConverter: Sendable {
    func convert(sportDataFromDevice: YCHealthDataStep) -> YuchengSportData {
        let sportData = YuchengSportData(startTimeStamp: Int64(sportDataFromDevice.startTimeStamp * 1000), endTimeStamp: Int64(sportDataFromDevice.endTimeStamp * 1000), distance: Int64(sportDataFromDevice.distance), steps: Int64(sportDataFromDevice.step), calories: Int64(sportDataFromDevice.calories))
        return sportData
    }
}
