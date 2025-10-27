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
  Future<bool> reconnect(int? reconnectTimeInSeconds) =>
      _api.reconnect(reconnectTimeInSeconds);

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
  Future<RealTimeBloodPressure> getRealTimeBloodPressure() =>
      _api.getRealTimeBloodPressure();

  @override
  Future<int> getRealTimeHeart() => _api.getRealTimeHeart();

  @override
  Future<int> getRealTimeBloodOxygen() => _api.getRealTimeBloodOxygen();
}
