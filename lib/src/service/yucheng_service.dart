import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
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
    with YuchengServiceNotifiersMixin, YuchengServiceBluetoothMixin {
  final YuchengBle _ble = const YuchengBle();
  final _deviceInfo = DeviceInfoPlugin();

  YuchengService();

  late final StreamSubscription<YuchengDeviceStateEvent> _deviceStateSub;
  late final StreamSubscription<YuchengDeviceEvent> _devicesSub;

  String? _deviceId;

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
            setSelectedDevice(YuchengDevice(
              index: event.index,
              deviceName: event.deviceName,
              uuid: event.mac,
              isReconnected: isReconnected,
            ));
            setDeviceConnected(isReconnected);
            setReconnecting(false);
            setReconnected(isReconnected);
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
          onSuccessfulReconnect: onSuccessfulReconnect,
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
    _deviceStateSub.cancel();
    _devicesSub.cancel();
    disposeNotifiers();
  }

  Future<bool> tryReconnect({
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
      setReconnected(false);
      setReconnecting(false);
      onBluetoothNotSupported?.call();
      return false;
    }

    final isBleOn = await isBluetoothOnWithTimer();
    if (!isBleOn) {
      setReconnected(false);
      setReconnecting(false);
      onBluetoothOff?.call();
      return false;
    }

    final isGranted = await requestPermissions();
    if (!isGranted) {
      setReconnected(false);
      setReconnecting(false);
      onPermissionsNotGranted?.call();
      return false;
    }

    if (isReconnected || isAnyDeviceConnected) {
      onDeviceConnectedYet?.call();
      setReconnected(false);
      setReconnecting(false);
      return false;
    }

    final isBleReconnected = await _ble.reconnect();
    if (isAnyDeviceConnected || isReconnected) {
      setReconnected(false);
      setReconnecting(false);
      return false;
    }
    setReconnected(isBleReconnected);
    setDeviceConnected(isBleReconnected);
    setReconnecting(false);
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

  Future<bool> tryConnectToDevice([YuchengDevice? device]) async {
    try {
      final deviceToConnect = device ?? selectedDevice;
      if (deviceToConnect == null) {
        throw YuchengServiceException('No device selected');
      }
      setSelectedDevice(device);
      setDeviceConnected(await _ble.connect(selectedDevice!));
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
      setSelectedDevice(null);
      setDeviceConnected(false);
      setReconnected(false);
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

  Future<String> getDeviceId() async {
    _deviceId ??= (Platform.isAndroid
        ? (await _deviceInfo.androidInfo).id
        : (await _deviceInfo.iosInfo).identifierForVendor);
    return _deviceId ?? '';
  }
}
