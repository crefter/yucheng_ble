import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:yucheng_ble/src/yucheng_ble.g.dart';

import 'yucheng_ble_method_channel.dart';

abstract class YuchengBlePlatform extends PlatformInterface {
  /// Constructs a YuchengBlePlatform.
  YuchengBlePlatform() : super(token: _token);

  static final Object _token = Object();

  static YuchengBlePlatform _instance = MethodChannelYuchengBle();

  /// The default instance of [YuchengBlePlatform] to use.
  ///
  /// Defaults to [MethodChannelYuchengBle].
  static YuchengBlePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [YuchengBlePlatform] when
  /// they register themselves.
  static set instance(YuchengBlePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  void startScanDevices(double? scanTimeInSeconds) {
    throw UnimplementedError('startScanDevices has not been implemented.');
  }

  Future<bool> isDeviceConnected(YuchengDevice device) {
    throw UnimplementedError('isDeviceConnected has not been implemented.');
  }

  Future<bool> connect(YuchengDevice? device) {
    throw UnimplementedError('connect has not been implemented.');
  }

  Future<void> disconnect() {
    throw UnimplementedError('disconnect has not been implemented.');
  }

  Future<List<YuchengSleepEvent?>> getSleepData() {
    throw UnimplementedError('getSleepData has not been implemented.');
  }

  Future<YuchengDevice?> getCurrentConnectedDevice() {
    throw UnimplementedError(
        'getCurrentConnectedDevice has not been implemented.');
  }

  Stream<YuchengDeviceEvent> devicesStream() {
    throw UnimplementedError('devices has not been implemented.');
  }

  Stream<YuchengSleepEvent> sleepDataStream() {
    throw UnimplementedError('sleepData has not been implemented.');
  }

  Stream<YuchengDeviceStateEvent> deviceStateStream() {
    throw UnimplementedError('deviceState has not been implemented.');
  }

  Future<bool> reconnect() {
    throw UnimplementedError('reconnect has not been implemented.');
  }
}
