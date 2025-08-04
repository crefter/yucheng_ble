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
  Stream<YuchengSleepHealthEvent> sleepHealthDataStream() => sleepHealthData();

  @override
  Stream<YuchengHealthEvent> healthDataStream() => healthData();

  @override
  Future<YuchengSleepHealthData> getSleepHealthData({
    int? startTimestamp,
    int? endTimestamp,
  }) =>
      _api.getSleepHealthData(
          startTimestamp: startTimestamp, endTimestamp: endTimestamp);

  @override
  Future<List<YuchengHealthData>> getHealthData({
    int? startTimestamp,
    int? endTimestamp,
  }) =>
      _api.getHealthData(
          startTimestamp: startTimestamp, endTimestamp: endTimestamp);

  @override
  Future<YuchengDeviceSettings?> getDeviceSettings() =>
      _api.getDeviceSettings();

  @override
  Future<bool> deleteSleepData() => _api.deleteSleepData();

  @override
  Future<bool> deleteHealthData() => _api.deleteHealthData();

  @override
  Future<bool> deleteSleepHealthData() => _api.deleteSleepHealthData();

  Future<bool> resetToFactory() => _api.resetToFactory();
}
