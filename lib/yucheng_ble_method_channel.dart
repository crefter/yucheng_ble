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
  Future<bool> connect(YuchengDevice device) => _api.connect(device);

  @override
  Future<void> disconnect() => _api.disconnect();

  @override
  Future<List<YuchengSleepEvent?>> getSleepData() => _api.getSleepData();

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
  Future<bool> reconnect() => _api.reconnect();
}
