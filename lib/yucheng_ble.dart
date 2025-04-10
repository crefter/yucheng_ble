import 'package:yucheng_ble/src/yucheng_ble.g.dart';

import 'yucheng_ble_platform_interface.dart';

extension YuchengSleepDataEventX on YuchengSleepDataEvent {
  DateTime get startDate {
    final startInMs = _timeStampInMs(startTimeStamp);
    return DateTime.fromMillisecondsSinceEpoch(startInMs);
  }

  DateTime get endDate {
    final endInMs = _timeStampInMs(endTimeStamp);
    return DateTime.fromMillisecondsSinceEpoch(endInMs);
  }

  int _timeStampInMs(int timeStamp) {
    final isMs = timeStamp.toString().length == 13;
    final timeStampInMs = isMs ? timeStamp : timeStamp * 1000;
    return timeStampInMs;
  }
}

extension YuchengSleepDataDetailX on YuchengSleepDataDetail {
  DateTime get startDate {
    final timeStampInMs = _timeStampInMs;
    return DateTime.fromMillisecondsSinceEpoch(
      timeStampInMs,
    );
  }

  DateTime get endDate {
    final timeStampInMs = _timeStampInMs;
    return DateTime.fromMillisecondsSinceEpoch(
        timeStampInMs + (duration * 1000));
  }

  int get _timeStampInMs {
    final isMs = startTimeStamp.toString().length == 13;
    final timeStampInMs = isMs ? startTimeStamp : startTimeStamp * 1000;
    return timeStampInMs;
  }
}

class YuchengBle {
  void startScanDevices(double? scanTimeInSeconds) =>
      YuchengBlePlatform.instance.startScanDevices(scanTimeInSeconds);

  Future<bool> isDeviceConnected(YuchengDevice? device) =>
      YuchengBlePlatform.instance.isDeviceConnected(device);

  Future<bool> connect(YuchengDevice device) =>
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
