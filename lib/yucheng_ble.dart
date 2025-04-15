import 'package:yucheng_ble/src/yucheng_ble.g.dart';

import 'yucheng_ble_platform_interface.dart';

extension YuchengSleepDataEventX on YuchengSleepData {
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

extension YuchengHealthDataX on YuchengHealthData {
  DateTime get startDate {
    final startInMs = _timeStampInMs;
    return DateTime.fromMillisecondsSinceEpoch(startInMs);
  }

  int get _timeStampInMs {
    final isMs = startTimestamp.toString().length == 13;
    final timeStampInMs = isMs ? startTimestamp : startTimestamp * 1000;
    return timeStampInMs;
  }
}

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
