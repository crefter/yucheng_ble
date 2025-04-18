import 'package:yucheng_ble/src/yucheng_ble.g.dart';

import 'yucheng_ble_platform_interface.dart';

class YuchengBle {
  const YuchengBle();

  Future<List<YuchengDevice>> startScanDevices(double? scanTimeInSeconds) =>
      YuchengBlePlatform.instance.startScanDevices(scanTimeInSeconds);

  Future<bool> isDeviceConnected(YuchengDevice? device) =>
      YuchengBlePlatform.instance.isDeviceConnected(device);

  Future<bool> connect(YuchengDevice device) =>
      YuchengBlePlatform.instance.connect(device);

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
  Future<List<YuchengHealthData>> getHealthData({
    DateTime? startTime,
    DateTime? endTime,
  }) =>
      YuchengBlePlatform.instance.getHealthData(
        startTimestamp: startTime?.millisecondsSinceEpoch,
        endTimestamp: endTime?.millisecondsSinceEpoch,
      );

  /// If startTime == null:
  /// start time = now - 7 days
  /// If endTime == null:
  /// end time = next day
  Future<YuchengSleepHealthData> getSleepHealthData({
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

  Stream<YuchengSleepHealthEvent> sleepHealthDataStream() =>
      YuchengBlePlatform.instance.sleepHealthDataStream();

  Future<bool> reconnect() => YuchengBlePlatform.instance.reconnect();

  Future<YuchengDeviceSettings?> getDeviceSettings() =>
      YuchengBlePlatform.instance.getDeviceSettings();
}
