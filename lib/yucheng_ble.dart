import 'package:yucheng_ble/src/yucheng_ble.g.dart';

import 'yucheng_ble_platform_interface.dart';

class YuchengBle {
  Future<List<YuchengDevice>> startScanDevices(double? scanTimeInSeconds) =>
      YuchengBlePlatform.instance.startScanDevices(scanTimeInSeconds);

  Future<bool> isDeviceConnected(YuchengDevice? device) =>
      YuchengBlePlatform.instance.isDeviceConnected(device);

  Future<bool> connect(YuchengDevice device) =>
      YuchengBlePlatform.instance.connect(device);

  Future<void> disconnect() => YuchengBlePlatform.instance.disconnect();

  Future<List<YuchengSleepData>> getSleepData() =>
      YuchengBlePlatform.instance.getSleepData();

  Future<List<YuchengHealthData>> getHealthData() =>
      YuchengBlePlatform.instance.getHealthData();

  Future<YuchengSleepHealthData> getSleepHealthData() =>
      YuchengBlePlatform.instance.getSleepHealthData();

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
}
