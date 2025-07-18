import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yucheng_ble/src/service/mixin/yucheng_service_permissions_mixin.dart';
import 'package:yucheng_ble/src/yucheng_ble.g.dart';
import 'package:yucheng_ble/yucheng_ble.dart';

import 'mixin/yucheng_service_bluetooth_mixin.dart';
import 'mixin/yucheng_service_notifiers_mixin.dart';

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
  final YuchengBle _ble = const YuchengBle();

  YuchengService();

  StreamSubscription<YuchengDeviceStateEvent>? _deviceStateSub;
  StreamSubscription<YuchengDeviceEvent>? _devicesSub;

  Stream<YuchengDeviceStateEvent> get deviceStateStream =>
      _ble.deviceStateStream();

  Stream<YuchengDeviceEvent> get devicesStream => _ble.devicesStream();

  Stream<YuchengSleepEvent> get sleepDataStream => _ble.sleepDataStream();

  Stream<YuchengHealthEvent> get healthDataStream => _ble.healthDataStream();

  Stream<YuchengSleepHealthEvent> get sleepHealthDataStream =>
      _ble.sleepHealthDataStream();

  Future<void> init({
    required Future<bool> Function()? shouldTryReconnect,
    VoidCallback? onBluetoothNotSupported,
    VoidCallback? onPermissionsNotGranted,
    VoidCallback? onDeviceConnectedYet,
    VoidCallback? onBluetoothOff,
    VoidCallback? onSuccessfulReconnect,
    VoidCallback? onFailedReconnect,
  }) async {
    _deviceStateSub?.cancel();
    _devicesSub?.cancel();

    _deviceStateSub = deviceStateStream.listen(
      (event) {
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
            onSuccessfulReconnect?.call();
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
          onBluetoothOff: onBluetoothOff,
        );
      },
      () async {
        onBluetoothOff?.call();
        setDeviceScanning(false);
        setReconnecting(false);
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
    int reconnectTimeInSeconds = 30,
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
      onBluetoothNotSupported?.call();
      return false;
    }

    final isBleOn = await isBluetoothOnWithTimer();
    if (!isBleOn) {
      setReconnecting(false);
      setReconnected(false);
      onBluetoothOff?.call();
      return false;
    }

    final isGranted = await requestPermissions();
    if (!isGranted) {
      setReconnecting(false);
      setReconnected(false);
      onPermissionsNotGranted?.call();
      return false;
    }

    if (isReconnected || isAnyDeviceConnected) {
      onDeviceConnectedYet?.call();
      setReconnecting(false);
      setReconnected(true);
      return true;
    }

    final isBleReconnected = await _ble.reconnect(reconnectTimeInSeconds);
    if (isAnyDeviceConnected || isReconnected) {
      setReconnecting(false);
      setReconnected(true);
      return true;
    }
    setReconnecting(false);
    setReconnected(isBleReconnected);
    setDeviceConnected(isBleReconnected);
    switch (isBleReconnected) {
      case true:
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
          await _ble.connect(selectedDevice!, connectTimeInSeconds));
      return isAnyDeviceConnected;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<YuchengSleepData>> tryGetSleepData({
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    try {
      final data = await _ble.getSleepData(
        startTime: startTime,
        endTime: endTime,
      );
      return data;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<YuchengHealthData>> tryGetHealthData({
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    try {
      final data = await _ble.getHealthData(
        startTime: startTime,
        endTime: endTime,
      );
      return data;
    } catch (e) {
      rethrow;
    }
  }

  Future<YuchengSleepHealthData> tryGetSleepHealthData({
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    try {
      final data = await _ble.getSleepHealthData(
        startTime: startTime,
        endTime: endTime,
      );
      return data;
    } catch (e) {
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

  Future<bool> deleteHealthData() async {
    try {
      return await _ble.deleteHealthData();
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> deleteSleepHealthData() async {
    try {
      return await _ble.deleteSleepHealthData();
    } catch (e) {
      rethrow;
    }
  }
}
