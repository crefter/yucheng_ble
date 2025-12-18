import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:yucheng_ble/export.dart';
import 'package:yucheng_ble/src/service/mixin/yucheng_service_permissions_mixin.dart';
import 'package:yucheng_ble/yucheng_ble.dart';

import 'mixin/yucheng_service_bluetooth_mixin.dart';
import 'mixin/yucheng_service_notifiers_mixin.dart';

class YuchengUserCanceledMeasurementException implements Exception {
  const YuchengUserCanceledMeasurementException();
}

class YuchengRealTimeMeasurementFailedException implements Exception {
  const YuchengRealTimeMeasurementFailedException();
}

class YuchengNoConnectionException implements Exception {
  const YuchengNoConnectionException();
}

class YuchengServiceException implements Exception {
  final String message;

  const YuchengServiceException(this.message);
}

/// If you need call init() before use
/// Must call dispose() after use (ex. in State.dispose())
final class YuchengService
    with
        YuchengServiceNotifiersMixin,
        YuchengServiceBluetoothMixin,
        YuchengServicePermissionsMixin {
  bool _hasDeviceReconnected = false;

  final YuchengBle _ble = const YuchengBle();

  YuchengService();

  StreamSubscription<YuchengDeviceStateEvent>? _deviceStateSub;
  StreamSubscription<YuchengDeviceEvent>? _devicesSub;

  Stream<YuchengDeviceStateEvent> get deviceStateStream =>
      _ble.deviceStateStream();

  Stream<YuchengDeviceEvent> get devicesStream => _ble.devicesStream();

  Stream<YuchengSleepEvent> get sleepDataStream => _ble.sleepDataStream();

  Stream<YuchengHealthEvent> get healthDataStream => _ble.healthDataStream();

  Stream<YuchengAllEvent> get sleepHealthDataStream => _ble.allDataStream();

  Stream<YuchengUpdateEvent> get updateDataStream => _ble.updateDataStream();

  Future<void> init({
    required Future<bool> Function()? shouldTryReconnect,
    VoidCallback? onBluetoothNotSupported,
    VoidCallback? onPermissionsNotGranted,
    VoidCallback? onDeviceConnectedYet,
    VoidCallback? onBluetoothOff,
    VoidCallback? onSuccessfulReconnect,
    VoidCallback? onFailedReconnect,
    String? uuid,
    String? deviceName,
  }) async {
    _deviceStateSub?.cancel();
    _devicesSub?.cancel();

    _deviceStateSub = deviceStateStream.listen(
      (event) {
        print("DEVICE STATE STREAM: $event");
        if (event is YuchengDeviceStateDataEvent) {
          if (event.state == YuchengDeviceState.readWriteOK) {
            setDeviceConnected(true);
          }
        } else if (event is YuchengDeviceStateErrorEvent) {
          setDeviceConnected(false);
        }
      },
    );

    _devicesSub = devicesStream.listen(
      (event) {
        if (event is YuchengDeviceDataEvent) {
          final isReconnected = event.isReconnected;
          if (isReconnected) {
            setReconnecting(false);
            setReconnected(isReconnected);
            setSelectedDevice(YuchengDevice(
              index: event.index,
              deviceName: event.deviceName,
              uuid: event.mac,
              isReconnected: isReconnected,
            ));
            setDeviceConnected(isReconnected);
            if (!_hasDeviceReconnected) {
              onSuccessfulReconnect?.call();
              _hasDeviceReconnected = true;
            }
          }
        }
      },
    );

    final shouldReconnect = await shouldTryReconnect?.call() ?? true;
    if (!shouldReconnect) return;

    listenBluetoothState(
      () async {
        final isSupported = await isBluetoothSupported();
        if (!isSupported) {
          setDeviceScanning(false);
          setReconnecting(false);
          onBluetoothNotSupported?.call();
          return;
        }

        final isGranted = await requestPermissions();
        if (!isGranted) {
          setDeviceScanning(false);
          setReconnecting(false);
          onPermissionsNotGranted?.call();
          return;
        }
        await tryReconnect(
          onPermissionsNotGranted: onPermissionsNotGranted,
          onBluetoothNotSupported: onBluetoothNotSupported,
          onDeviceConnectedYet: onDeviceConnectedYet,
          onFailedReconnect: onFailedReconnect,
          onSuccessfulReconnect: onSuccessfulReconnect,
          onBluetoothOff: onBluetoothOff,
          uuid: uuid,
          deviceName: deviceName,
        );
      },
      () async {
        onBluetoothOff?.call();
        setDeviceScanning(false);
        setReconnecting(false);
        setDeviceConnected(false);
        setReconnected(false);
      },
    );
  }

  void dispose() {
    cancelListenBluetoothState();
    _deviceStateSub?.cancel();
    _devicesSub?.cancel();
    disposeNotifiers();
  }

  Future<bool> tryReconnect({
    int reconnectTimeInSeconds = 45,
    String? uuid,
    String? deviceName,
    VoidCallback? onBluetoothNotSupported,
    VoidCallback? onBluetoothOff,
    VoidCallback? onPermissionsNotGranted,
    VoidCallback? onDeviceConnectedYet,
    VoidCallback? onSuccessfulReconnect,
    VoidCallback? onFailedReconnect,
  }) async {
    setReconnecting(true);
    final isSupported = await isBluetoothSupported();
    if (!isSupported) {
      setReconnecting(false);
      setReconnected(false);
      setDeviceConnected(false);
      onBluetoothNotSupported?.call();
      return false;
    }

    final isBleOn = await isBluetoothOnWithTimer();
    if (!isBleOn) {
      setReconnecting(false);
      setReconnected(false);
      setDeviceConnected(false);
      onBluetoothOff?.call();
      return false;
    }

    final isGranted = await requestPermissions();
    if (!isGranted) {
      setReconnecting(false);
      setReconnected(false);
      setDeviceConnected(false);
      onPermissionsNotGranted?.call();
      return false;
    }

    final lastConnectedDevice = await _ble.getCurrentConnectedDevice();
    final hasLastDevice = lastConnectedDevice != null;
    final isMacAddressNotNull = uuid != null;
    final isDeviceNameNotNull = deviceName != null;
    if ((!hasLastDevice && (isMacAddressNotNull || isDeviceNameNotNull)) ||
        (isMacAddressNotNull && lastConnectedDevice?.uuid != uuid) ||
        (isDeviceNameNotNull &&
            lastConnectedDevice?.deviceName != deviceName)) {
      final scannedDevices = await scanDevices(
        onBluetoothNotSupported: onBluetoothNotSupported,
        onPermissionsNotGranted: onPermissionsNotGranted,
        onBluetoothOffIos: onBluetoothOff,
        onBluetoothOffAndroid: onBluetoothOff,
      );
      if (scannedDevices.isEmpty) {
        setReconnecting(false);
        setReconnected(false);
        onFailedReconnect?.call();
        return false;
      }
      final device = scannedDevices.firstWhereOrNull(
          (d) => d.uuid == uuid || d.deviceName == deviceName);
      if (device == null) {
        setReconnecting(false);
        setReconnected(false);
        onFailedReconnect?.call();
        return false;
      }
      final isConnected = await tryConnectToDevice(device);
      setReconnecting(false);
      setReconnected(isConnected);
      setDeviceConnected(isConnected);
      switch (isConnected) {
        case true:
          _hasDeviceReconnected = true;
          onSuccessfulReconnect?.call();
        case false:
          onFailedReconnect?.call();
      }

      return isConnected;
    }

    final isBleReconnected = await _ble.reconnect(uuid);
    setReconnecting(false);
    setReconnected(isBleReconnected);
    setDeviceConnected(isBleReconnected);
    switch (isBleReconnected) {
      case true:
        _hasDeviceReconnected = true;
        onSuccessfulReconnect?.call();
      case false:
        onFailedReconnect?.call();
    }

    return isBleReconnected;
  }

  Future<List<YuchengDevice>> scanDevices({
    VoidCallback? onBluetoothNotSupported,
    VoidCallback? onPermissionsNotGranted,
    VoidCallback? onBluetoothOffIos,
    VoidCallback? onBluetoothOffAndroid,
  }) async {
    final isSupported = await isBluetoothSupported();
    if (!isSupported) {
      setDeviceScanning(false);
      onBluetoothNotSupported?.call();
      return [];
    }

    final isGranted = await requestPermissions();
    if (!isGranted) {
      setDeviceScanning(false);
      onPermissionsNotGranted?.call();
      return [];
    }

    if (await isBluetoothOnWithTimer()) {
      setDeviceScanning(true);
      final devices = await _ble.startScanDevices(null);
      setDeviceScanning(false);
      return devices;
    } else {
      setDeviceScanning(false);
      await tryTurnOnBluetooth();
      final isOn = await isBluetoothOn();
      if (Platform.isIOS) {
        onBluetoothOffIos?.call();
      } else if (Platform.isAndroid && !isOn) {
        onBluetoothOffAndroid?.call();
      }
      return [];
    }
  }

  Future<bool> tryConnectToDevice(
      [YuchengDevice? device, int connectTimeInSeconds = 30]) async {
    try {
      final deviceToConnect = device ?? selectedDevice;
      if (deviceToConnect == null) {
        throw YuchengServiceException('No device selected');
      }
      setSelectedDevice(device);
      setDeviceConnected(
        await _ble.connect(deviceToConnect, connectTimeInSeconds),
      );
      return isAnyDeviceConnected;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<YuchengSleepData>> tryGetSleepData({
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final (start, end) = DateTime.now()._weeklyDateRange;
    final startDate = startTime ?? start;
    final endDate = endTime ?? end;
    try {
      final data = await _ble.getSleepData(
        startTime: startDate,
        endTime: endDate,
      );

      final filteredData =
          data.where((e) => e.isInRange(startDate, endDate)).toList();
      return filteredData;
    } catch (e) {
      if (e is PlatformException) {
        if (e.code.contains('NoConnectionException')) {
          throw const YuchengNoConnectionException();
        }
      }
      rethrow;
    }
  }

  Future<YuchengHealthSportData> tryGetHealthSportData({
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final (start, end) = DateTime.now()._weeklyDateRange;
    final startDate = startTime ?? start;
    final endDate = endTime ?? end;
    try {
      final data = await _ble.getHealthSportData(
        startTime: startDate,
        endTime: endDate,
      );

      final filteredData = data.inDateRange(startDate, endDate);
      return filteredData;
    } catch (e) {
      if (e is PlatformException) {
        if (e.code.contains('NoConnectionException')) {
          throw const YuchengNoConnectionException();
        }
      }
      rethrow;
    }
  }

  Future<YuchengAllData> tryGetAllData({
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final (start, end) = DateTime.now()._weeklyDateRange;
    final startDate = startTime ?? start;
    final endDate = endTime ?? end;
    try {
      final data = await _ble.getAllData(
        startTime: startDate,
        endTime: endDate,
      );

      final filteredData = data.inDateRange(startDate, endDate);
      return filteredData;
    } catch (e) {
      if (e is PlatformException) {
        if (e.code.contains('NoConnectionException')) {
          throw const YuchengNoConnectionException();
        }
      }
      rethrow;
    }
  }

  Future<bool> isDeviceConnected(YuchengDevice? device) async {
    try {
      return await _ble.isDeviceConnected(device);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> disconnect() async {
    try {
      await _ble.disconnect();
      setReconnected(false);
      setSelectedDevice(null);
      setDeviceConnected(false);
      setDeviceSettings(null);
    } catch (e) {
      rethrow;
    }
  }

  Future<YuchengDevice?> getCurrentConnectedDevice() async {
    try {
      setSelectedDevice(await _ble.getCurrentConnectedDevice());
      return selectedDevice;
    } catch (e) {
      rethrow;
    }
  }

  Future<YuchengDeviceSettings?> getDeviceSettings() async {
    try {
      setDeviceSettings(await _ble.getDeviceSettings());
      return deviceSettings;
    } catch (e) {
      if (e is PlatformException) {
        if (e.code.contains('NoConnectionException')) {
          throw const YuchengNoConnectionException();
        }
      }
      rethrow;
    }
  }

  Future<bool> deleteSleepData() async {
    try {
      return await _ble.deleteSleepData();
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> deleteHealthSportData() async {
    try {
      return await _ble.deleteHealthSportData();
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> deleteAllData() async {
    try {
      return await _ble.deleteAllData();
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> resetToFactory() async {
    try {
      final isReset = await _ble.resetToFactory();
      if (isReset) {
        setReconnecting(false);
        setReconnected(false);
        setSelectedDevice(null);
        setDeviceConnected(false);
      }
      return isReset;
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> updateFirmware(String pathToFile,
      [YuchengDevice? device]) async {
    try {
      final deviceToConnect = device ?? selectedDevice;
      if (deviceToConnect == null) {
        throw YuchengServiceException('No device selected');
      }
      setUpdatingFirmware(true);
      final result = await _ble.updateFirmware(deviceToConnect, pathToFile);
      setUpdatingFirmware(false);
      return result;
    } catch (e) {
      setUpdatingFirmware(false);
      rethrow;
    }
  }

  Future<int?> getHealthMonitorInterval() async {
    try {
      return await _ble.getHealthMonitorInterval();
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> setHealthMonitorInterval(int interval) async {
    try {
      return await _ble.setHealthMonitorInterval(interval);
    } catch (e) {
      rethrow;
    }
  }

  Future<YuchengHealthSportData> getRealTimeHealthRecord() async {
    try {
      return await _ble.getRealTimeHealthRecord();
    } catch (e) {
      if (e is PlatformException) {
        if (e.code.contains('UserExitedMeasurementException')) {
          throw const YuchengUserCanceledMeasurementException();
        }
      }
      rethrow;
    }
  }

  Future<YuchengRealtimeDataSingleResult?> startMeasurementBloodOxygen() async {
    try {
      final data = await _ble.startMeasurementBloodOxygen();
      if (data == null) return null;
      return YuchengRealtimeDataSingleResult(value: data);
    } catch (e) {
      if (e is PlatformException) {
        if (e.code.contains('UserExitedMeasurementException')) {
          throw const YuchengUserCanceledMeasurementException();
        } else if (e.code.contains('RealTimeMeasurementFailedException')) {
          throw const YuchengRealTimeMeasurementFailedException();
        } else if (e.code.contains('NoConnectionException')) {
          throw const YuchengNoConnectionException();
        }
      }
      rethrow;
    }
  }

  Future<YuchengRealtimeDataSingleResult?> startMeasurementHeart() async {
    try {
      final data = await _ble.startMeasurementHeart();
      if (data == null) return null;
      return YuchengRealtimeDataSingleResult(value: data);
    } catch (e) {
      if (e is PlatformException) {
        if (e.code.contains('UserExitedMeasurementException')) {
          throw const YuchengUserCanceledMeasurementException();
        } else if (e.code.contains('RealTimeMeasurementFailedException')) {
          throw const YuchengRealTimeMeasurementFailedException();
        } else if (e.code.contains('NoConnectionException')) {
          throw const YuchengNoConnectionException();
        }
      }
      rethrow;
    }
  }

  Future<YuchengRealtimeDataBloodPressureResult?>
      startMeasurementBloodPressure() async {
    try {
      final data = await _ble.startMeasurementBloodPressure();
      if (data == null) return null;
      return YuchengRealtimeDataBloodPressureResult(
          sbp: data.sbp, dbp: data.dbp);
    } catch (e) {
      if (e is PlatformException) {
        if (e.code.contains('UserExitedMeasurementException')) {
          throw const YuchengUserCanceledMeasurementException();
        } else if (e.code.contains('RealTimeMeasurementFailedException')) {
          throw const YuchengRealTimeMeasurementFailedException();
        } else if (e.code.contains('NoConnectionException')) {
          throw const YuchengNoConnectionException();
        }
      }
      rethrow;
    }
  }

  Future<bool> stopMeasurementBloodOxygen() async {
    try {
      return await _ble.stopMeasurementBloodOxygen();
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> stopMeasurementBloodPressure() async {
    try {
      return await _ble.stopMeasurementBloodPressure();
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> stopMeasurementHeart() async {
    try {
      return await _ble.stopMeasurementHeart();
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> calibrateBloodPressure(int sbp, int dbp) async {
    try {
      return await _ble.calibrateBloodPressure(sbp, dbp);
    } catch (e) {
      rethrow;
    }
  }
}

extension FirstWhereOrNullX<T> on Iterable<T> {
  /// returns first item to satisfy `test`, else null
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) {
        return element;
      }
    }
    return null;
  }
}

extension on DateTime {
  /// Returns a tuple of (startDate, endDate) from current date
  /// endDate is end of current day
  /// startDate is endDate - 7 days (week)
  (DateTime startDate, DateTime endDate) get _weeklyDateRange {
    final endDate = DateTime(year, month, day, 23, 59, 59, 999, 999);
    final startDate = endDate.subtract(const Duration(days: 7));

    return (startDate, endDate);
  }
}
