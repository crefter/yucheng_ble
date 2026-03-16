import 'package:yucheng_ble/src/yucheng_ble.g.dart';

import 'yucheng_ble_platform_interface.dart';

/// An implementation of [YuchengBlePlatform] that uses method channels.
class MethodChannelYuchengBle extends YuchengBlePlatform {
  final YuchengHostApi _api = YuchengHostApi();

  @override
  Future<List<YuchengDevice>> startScanDevices(double? scanTimeInSeconds) =>
      _api.startScanDevices(scanTimeInSeconds);

  @override
  Future<bool> isDeviceConnected(YuchengDevice? device) =>
      _api.isDeviceConnected(device);

  @override
  Future<bool> connect(YuchengDevice device, int? connectTimeInSeconds) =>
      _api.connect(device, connectTimeInSeconds);

  @override
  Future<void> disconnect() => _api.disconnect();

  @override
  Future<List<YuchengSleepData>> getSleepData({
    int? startTimestamp,
    int? endTimestamp,
  }) =>
      _api.getSleepData(
          startTimestamp: startTimestamp, endTimestamp: endTimestamp);

  @override
  Future<YuchengDevice?> getCurrentConnectedDevice() =>
      _api.getCurrentConnectedDevice();

  @override
  Stream<YuchengDeviceEvent> devicesStream() => devices();

  @override
  Stream<YuchengSleepEvent> sleepDataStream() => sleepData();

  @override
  Stream<YuchengDeviceStateEvent> deviceStateStream() => deviceState();

  @override
  Future<bool> reconnect(String? uuid, [int? reconnectTimeInSeconds]) =>
      _api.reconnect(uuid, reconnectTimeInSeconds);

  @override
  Stream<YuchengAllEvent> allDataStream() => allData();

  @override
  Stream<YuchengHealthEvent> healthDataStream() => healthData();

  @override
  Stream<YuchengUpdateEvent> updateDataStream() => updateData();

  @override
  Future<YuchengAllData> getSleepHealthData({
    int? startTimestamp,
    int? endTimestamp,
  }) =>
      _api.getAllData(
          startTimestamp: startTimestamp, endTimestamp: endTimestamp);

  @override
  Future<YuchengHealthSportData> getHealthSportData({
    int? startTimestamp,
    int? endTimestamp,
  }) =>
      _api.getHealthSportData(
          startTimestamp: startTimestamp, endTimestamp: endTimestamp);

  @override
  Future<YuchengDeviceSettings?> getDeviceSettings() =>
      _api.getDeviceSettings();

  @override
  Future<bool> deleteSleepData() => _api.deleteSleepData();

  @override
  Future<bool> deleteHealthSportData() => _api.deleteHealthSportData();

  @override
  Future<bool> deleteAllData() => _api.deleteAllData();

  @override
  Future<bool> resetToFactory() => _api.resetToFactory();

  @override
  Future<bool> updateFirmware(YuchengDevice device, String pathToFile) =>
      _api.updateFirmware(device, pathToFile);

  @override
  Future<int?> getHealthMonitorInterval() => _api.getHealthMonitorInterval();

  @override
  Future<bool> setHealthMonitorInterval(int interval) =>
      _api.setHealthMonitorInterval(interval);

  @override
  Future<YuchengHealthSportData> getRealTimeHealthRecord() =>
      _api.getRealTimeHealthRecord();

  @override
  Future<RealTimeBloodPressure?> startMeasurementBloodPressure() =>
      _api.startMeasurementBloodPressure();

  @override
  Future<int?> startMeasurementHeart() => _api.startMeasurementHeart();

  @override
  Future<int?> startMeasurementBloodOxygen() =>
      _api.startMeasurementBloodOxygen();

  @override
  Future<bool> stopMeasurementBloodOxygen() =>
      _api.stopMeasurementBloodOxygen();

  @override
  Future<bool> stopMeasurementBloodPressure() =>
      _api.stopMeasurementBloodPressure();

  @override
  Future<bool> stopMeasurementHeart() => _api.stopMeasurementHeart();

  @override
  Future<bool> calibrateBloodPressure(int sbp, int dbp) =>
      _api.calibrateBloodPressure(sbp, dbp);

  @override
  Future<bool> turnOnBackgroundService(int delayInMinutes) =>
      _api.turnOnBackgroundService(delayInMinutes);

  @override
  Future<bool> turnOffBackgroundService() => _api.turnOffBackgroundService();

  @override
  Future<bool> canLaunchBackgroundService() =>
      _api.canLaunchBackgroundService();

  @override
  Future<void> setFlavor(String flavorName) => _api.setFlavor(flavorName);

  @override
  Future<void> setToken(YuchengToken? token) => _api.setToken(token);

  @override
  Future<YuchengToken?> getToken() => _api.getToken();
}
