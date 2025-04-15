//
//  YuchengSleepDataConverter.swift
//  Pods
//
//  Created by Maxim Zarechnev on 10.04.2025.
//

import YCProductSDK

final class YuchengHealthDataConverter: Sendable {
    func convert(healthDataFromDevice: YCHealthDataCombinedData) -> YuchengHealthData {
        let tempInt = Int64(healthDataFromDevice.temperature)
        let tempFloat = Int64((healthDataFromDevice.temperature - healthDataFromDevice.temperature.rounded(.down)) * 100)
        
        let bodyInt = Int64(healthDataFromDevice.fat)
        let bodyFloat = Int64((healthDataFromDevice.fat - healthDataFromDevice.fat.rounded(.down)) * 100)
        
        let healthData = YuchengHealthData(heartValue: Int64(healthDataFromDevice.heartRate), hrvValue: Int64(healthDataFromDevice.hrv), cvrrValue: Int64(healthDataFromDevice.cvrr), OOValue: Int64(healthDataFromDevice.bloodOxygen), stepValue: Int64(healthDataFromDevice.step), DBPValue: Int64(healthDataFromDevice.diastolicBloodPressure), tempIntValue: tempInt, tempFloatValue: tempFloat, startTimestamp: Int64(healthDataFromDevice.startTimeStamp), SBPValue: Int64(healthDataFromDevice.systolicBloodPressure), respiratoryRateValue: Int64(healthDataFromDevice.respirationRate), bodyFatIntValue: bodyInt, bodyFatFloatValue: bodyFloat, bloodSugarValue: Int64(healthDataFromDevice.bloodGlucose))
        return healthData
    }
}
