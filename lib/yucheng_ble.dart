import 'package:yucheng_ble/src/yucheng_ble.g.dart';

import 'yucheng_ble_platform_interface.dart';

class YuchengBle {
  const YuchengBle();

  Future<List<YuchengDevice>> startScanDevices(double? scanTimeInSeconds) =>
      YuchengBlePlatform.instance.startScanDevices(scanTimeInSeconds);

  Future<bool> isDeviceConnected(YuchengDevice? device) =>
      YuchengBlePlatform.instance.isDeviceConnected(device);

  Future<bool> connect(YuchengDevice device, int? connectTimeInSeconds) =>
      YuchengBlePlatform.instance.connect(device, connectTimeInSeconds);

  Future<void> disconnect() => YuchengBlePlatform.instance.disconnect();

  /// If startTime == null:
  /// start time = now - 7 days
  /// If endTime == null:
  /// end time = next day
  Future<List<YuchengSleepData>> getSleepData({
    DateTime? startTime,
    DateTime? endTime,
  }) =>
      YuchengBlePlatform.instance.getSleepData(
        startTimestamp: startTime?.millisecondsSinceEpoch,
        endTimestamp: endTime?.millisecondsSinceEpoch,
      );

  /// If startTime == null:
  /// start time = now - 7 days
  /// If endTime == null:
  /// end time = next day
  Future<YuchengHealthSportData> getHealthSportData({
    DateTime? startTime,
    DateTime? endTime,
  }) =>
      YuchengBlePlatform.instance.getHealthSportData(
        startTimestamp: startTime?.millisecondsSinceEpoch,
        endTimestamp: endTime?.millisecondsSinceEpoch,
      );

  /// If startTime == null:
  /// start time = now - 7 days
  /// If endTime == null:
  /// end time = next day
  Future<YuchengAllData> getAllData({
    DateTime? startTime,
    DateTime? endTime,
  }) =>
      YuchengBlePlatform.instance.getSleepHealthData(
        startTimestamp: startTime?.millisecondsSinceEpoch,
        endTimestamp: endTime?.millisecondsSinceEpoch,
      );

  Future<YuchengDevice?> getCurrentConnectedDevice() =>
      YuchengBlePlatform.instance.getCurrentConnectedDevice();

  Stream<YuchengDeviceEvent> devicesStream() =>
      YuchengBlePlatform.instance.devicesStream();

  Stream<YuchengSleepEvent> sleepDataStream() =>
      YuchengBlePlatform.instance.sleepDataStream();

  Stream<YuchengDeviceStateEvent> deviceStateStream() =>
      YuchengBlePlatform.instance.deviceStateStream();

  Stream<YuchengHealthEvent> healthDataStream() =>
      YuchengBlePlatform.instance.healthDataStream();

  Stream<YuchengAllEvent> allDataStream() =>
      YuchengBlePlatform.instance.allDataStream();

  Stream<YuchengUpdateEvent> updateDataStream() =>
      YuchengBlePlatform.instance.updateDataStream();

  Future<bool> reconnect(int? reconnectTimeInSeconds) =>
      YuchengBlePlatform.instance.reconnect(reconnectTimeInSeconds);

  Future<YuchengDeviceSettings?> getDeviceSettings() =>
      YuchengBlePlatform.instance.getDeviceSettings();

  Future<bool> deleteSleepData() =>
      YuchengBlePlatform.instance.deleteSleepData();

  Future<bool> deleteHealthSportData() =>
      YuchengBlePlatform.instance.deleteHealthSportData();

  Future<bool> deleteAllData() => YuchengBlePlatform.instance.deleteAllData();

  Future<bool> resetToFactory() => YuchengBlePlatform.instance.resetToFactory();

  Future<bool> updateFirmware(YuchengDevice device, String pathToFile) =>
      YuchengBlePlatform.instance.updateFirmware(device, pathToFile);

  Future<int?> getHealthMonitorInterval() =>
      YuchengBlePlatform.instance.getHealthMonitorInterval();

  Future<bool> setHealthMonitorInterval(int interval) =>
      YuchengBlePlatform.instance.setHealthMonitorInterval(interval);

  Future<YuchengHealthSportData> getRealTimeHealthRecord() =>
      YuchengBlePlatform.instance.getRealTimeHealthRecord();

  Future<RealTimeBloodPressure> getRealTimeBloodPressure() =>
      YuchengBlePlatform.instance.getRealTimeBloodPressure();

  Future<int> getRealTimeHeart() =>
      YuchengBlePlatform.instance.getRealTimeHeart();

  Future<int> getRealTimeBloodOxygen() =>
      YuchengBlePlatform.instance.getRealTimeBloodOxygen();
}
