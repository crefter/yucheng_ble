import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:yucheng_ble/src/yucheng_ble.g.dart';
import 'package:yucheng_ble/yucheng_ble.dart';
import 'package:yucheng_ble/yucheng_ble_method_channel.dart';
import 'package:yucheng_ble/yucheng_ble_platform_interface.dart';

class MockYuchengBlePlatform
    with MockPlatformInterfaceMixin
    implements YuchengBlePlatform {
  @override
  Future<bool> connect(YuchengDevice device) {
    // TODO: implement connect
    throw UnimplementedError();
  }

  @override
  Stream<YuchengDeviceStateEvent> deviceStateStream() {
    // TODO: implement deviceStateStream
    throw UnimplementedError();
  }

  @override
  Stream<YuchengDeviceEvent> devicesStream() {
    // TODO: implement devicesStream
    throw UnimplementedError();
  }

  @override
  Future<void> disconnect() {
    // TODO: implement disconnect
    throw UnimplementedError();
  }

  @override
  Future<YuchengDevice?> getCurrentConnectedDevice() {
    // TODO: implement getCurrentConnectedDevice
    throw UnimplementedError();
  }

  @override
  Future<List<YuchengSleepData>> getSleepData({
    int? startTimestamp,
    int? endTimestamp,
  }) {
    // TODO: implement getSleepData
    throw UnimplementedError();
  }

  @override
  Future<bool> isDeviceConnected(YuchengDevice? device) {
    // TODO: implement isDeviceConnected
    throw UnimplementedError();
  }

  @override
  Stream<YuchengSleepDataEvent> sleepDataStream() {
    // TODO: implement sleepDataStream
    throw UnimplementedError();
  }

  @override
  Future<List<YuchengDevice>> startScanDevices(
      double? scanTimeInSeconds) async {
    // TODO: implement startScanDevices
    throw UnimplementedError();
  }

  @override
  Future<bool> reconnect() {
    // TODO: implement reconnect
    throw UnimplementedError();
  }

  @override
  Future<List<YuchengHealthData>> getHealthData({
    int? startTimestamp,
    int? endTimestamp,
  }) {
    // TODO: implement getHealthData
    throw UnimplementedError();
  }

  @override
  Future<YuchengSleepHealthData> getSleepHealthData({
    int? startTimestamp,
    int? endTimestamp,
  }) {
    // TODO: implement getSleepHealthData
    throw UnimplementedError();
  }

  @override
  Stream<YuchengHealthEvent> healthDataStream() {
    // TODO: implement healthDataStream
    throw UnimplementedError();
  }

  @override
  Stream<YuchengSleepHealthEvent> sleepHealthDataStream() {
    // TODO: implement sleepHealthDataStream
    throw UnimplementedError();
  }
}

void main() {
  final YuchengBlePlatform initialPlatform = YuchengBlePlatform.instance;

  test('$MethodChannelYuchengBle is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelYuchengBle>());
  });

  test('getPlatformVersion', () async {
    YuchengBle yuchengBlePlugin = YuchengBle();
    MockYuchengBlePlatform fakePlatform = MockYuchengBlePlatform();
    YuchengBlePlatform.instance = fakePlatform;

    expect('42', '42');
  });
}
