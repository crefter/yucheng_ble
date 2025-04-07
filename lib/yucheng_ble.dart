import 'package:yucheng_ble/src/yucheng_ble.g.dart';

import 'yucheng_ble_platform_interface.dart';

extension YuchengSleepDataEventX on YuchengSleepDataEvent {
  DateTime get startDate => DateTime.fromMillisecondsSinceEpoch(startTimeStamp);
  DateTime get endDate => DateTime.fromMillisecondsSinceEpoch(endTimeStamp);
}

extension YuchengSleepDataDetailX on YuchengSleepDataDetail {
  DateTime get startDate => DateTime.fromMillisecondsSinceEpoch(startTimeStamp);
  DateTime get endDate =>
      DateTime.fromMillisecondsSinceEpoch(startTimeStamp + (duration * 1000));
}

class YuchengBle {
  void startScanDevices(double? scanTimeInSeconds) =>
      YuchengBlePlatform.instance.startScanDevices(scanTimeInSeconds);

  Future<bool> isDeviceConnected(YuchengDevice device) =>
      YuchengBlePlatform.instance.isDeviceConnected(device);

  Future<bool> connect(YuchengDevice? device) =>
      YuchengBlePlatform.instance.connect(device);

  Future<void> disconnect() => YuchengBlePlatform.instance.disconnect();

  Future<List<YuchengSleepEvent?>> getSleepData() =>
      YuchengBlePlatform.instance.getSleepData();

  Future<YuchengDevice?> getCurrentConnectedDevice() =>
      YuchengBlePlatform.instance.getCurrentConnectedDevice();

  Stream<YuchengDeviceEvent> devicesStream() =>
      YuchengBlePlatform.instance.devicesStream();

  Stream<YuchengSleepEvent> sleepDataStream() =>
      YuchengBlePlatform.instance.sleepDataStream();

  Stream<YuchengDeviceStateEvent> deviceStateStream() =>
      YuchengBlePlatform.instance.deviceStateStream();

  Future<bool> reconnect() => YuchengBlePlatform.instance.reconnect();
}
