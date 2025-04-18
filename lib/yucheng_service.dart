import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:yucheng_ble/src/yucheng_ble.g.dart';
import 'package:yucheng_ble/yucheng_ble.dart';

/// Must call init() before use
/// Must call dispose() after use
final class YuchengService {
  final YuchengBle _ble = const YuchengBle();
  final _deviceInfo = DeviceInfoPlugin();

  YuchengService();

  late final StreamSubscription<YuchengDeviceStateEvent> _deviceStateSub;
  late final StreamSubscription<YuchengDeviceEvent> _devicesSub;
  late final StreamSubscription<BluetoothAdapterState> _bluetoothStateSub;

  final ValueNotifier<YuchengDevice?> selectedDeviceNotifier =
      ValueNotifier(null);
  final ValueNotifier<YuchengDeviceSettings?> deviceSettingsNotifier =
      ValueNotifier(null);
  final ValueNotifier<bool> isDeviceScanningNotifier = ValueNotifier(false);
  final ValueNotifier<bool> isDeviceConnectedNotifier = ValueNotifier(false);
  final ValueNotifier<bool> isReconnectedNotifier = ValueNotifier(false);
  final ValueNotifier<bool> isReconnectingNotifier = ValueNotifier(false);
  String? _deviceId;

  Stream<YuchengDeviceStateEvent> get deviceStateStream =>
      _ble.deviceStateStream();

  Stream<YuchengDeviceEvent> get devicesStream => _ble.devicesStream();

  Stream<YuchengSleepEvent> get sleepDataStream => _ble.sleepDataStream();

  Stream<YuchengHealthEvent> get healthDataStream => _ble.healthDataStream();

  Stream<YuchengSleepHealthEvent> get sleepHealthDataStream =>
      _ble.sleepHealthDataStream();

  bool get isDeviceScanning => isDeviceScanningNotifier.value;

  bool get isAnyDeviceConnected => isDeviceConnectedNotifier.value;

  bool get isReconnected => isReconnectedNotifier.value;

  bool get isReconnecting => isReconnectingNotifier.value;

  YuchengDevice? get selectedDevice => selectedDeviceNotifier.value;
  YuchengDeviceSettings? get deviceSettings => deviceSettingsNotifier.value;

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
            isDeviceConnectedNotifier.value = true;
          }
        } else if (event is YuchengDeviceStateErrorEvent) {
          isDeviceConnectedNotifier.value = false;
        }
      },
    );

    _devicesSub = devicesStream.listen(
      (event) {
        if (event is YuchengDeviceDataEvent) {
          final isReconnected = event.isReconnected;
          if (isReconnected) {
            selectedDeviceNotifier.value = YuchengDevice(
              index: event.index,
              deviceName: event.deviceName,
              uuid: event.mac,
              isReconnected: isReconnected,
            );
            isDeviceConnectedNotifier.value = isReconnected;
            isReconnectingNotifier.value = false;
            isReconnectedNotifier.value = isReconnected;
          }
        }
      },
    );

    final shouldReconnect = await shouldTryReconnect?.call() ?? true;
    if (!shouldReconnect) return;

    _bluetoothStateSub = FlutterBluePlus.adapterState.listen(
      (event) async {
        if (event == BluetoothAdapterState.on) {
          final isSupported = await isBluetoothSupported();
          if (!isSupported) {
            isDeviceScanningNotifier.value = false;
            onBluetoothNotSupported?.call();
            return;
          }

          final isGranted = await requestPermissions();
          if (!isGranted) {
            isDeviceScanningNotifier.value = false;
            onPermissionsNotGranted?.call();
            return;
          }
          await tryReconnect(
            onPermissionsNotGranted: onPermissionsNotGranted,
            onBluetoothNotSupported: onBluetoothNotSupported,
            onDeviceConnectedYet: onDeviceConnectedYet,
            onSuccessfulReconnect: onSuccessfulReconnect,
            onFailedReconnect: onFailedReconnect,
          );
        } else if (event == BluetoothAdapterState.off) {
          onBluetoothOff?.call();
          isDeviceScanningNotifier.value = false;
        }
      },
    );
  }

  void updateUiOnNotifiersChanges(VoidCallback update) {
    isDeviceScanningNotifier.addListener(update);
    isReconnectedNotifier.addListener(update);
    isDeviceConnectedNotifier.addListener(update);
    selectedDeviceNotifier.addListener(update);
    isReconnectingNotifier.addListener(update);
    deviceSettingsNotifier.addListener(update);
  }

  void dispose() {
    _bluetoothStateSub.cancel();
    _deviceStateSub.cancel();
    _devicesSub.cancel();
    isDeviceScanningNotifier.dispose();
    isReconnectedNotifier.dispose();
    isDeviceConnectedNotifier.dispose();
    selectedDeviceNotifier.dispose();
    isReconnectingNotifier.dispose();
    deviceSettingsNotifier.dispose();
  }

  Future<bool> tryReconnect({
    VoidCallback? onBluetoothNotSupported,
    VoidCallback? onPermissionsNotGranted,
    VoidCallback? onDeviceConnectedYet,
    VoidCallback? onSuccessfulReconnect,
    VoidCallback? onFailedReconnect,
  }) async {
    isReconnectingNotifier.value = true;
    final isSupported = await isBluetoothSupported();
    if (!isSupported) {
      isReconnectedNotifier.value = false;
      isDeviceScanningNotifier.value = false;
      isReconnectingNotifier.value = false;
      onBluetoothNotSupported?.call();
      return false;
    }

    final isGranted = await requestPermissions();
    if (!isGranted) {
      isReconnectedNotifier.value = false;
      isDeviceScanningNotifier.value = false;
      isReconnectingNotifier.value = false;
      onPermissionsNotGranted?.call();
      return false;
    }

    if (isReconnected || isAnyDeviceConnected) {
      onDeviceConnectedYet?.call();
      isReconnectedNotifier.value = false;
      isReconnectingNotifier.value = false;
      return false;
    }
    final isBleReconnected = await _ble.reconnect();
    isReconnectedNotifier.value = isBleReconnected;
    isDeviceConnectedNotifier.value = isBleReconnected;
    isReconnectingNotifier.value = false;
    switch (isBleReconnected) {
      case true:
        onSuccessfulReconnect?.call();
      case false:
        onFailedReconnect?.call();
    }
    ;
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
      isDeviceScanningNotifier.value = false;
      onBluetoothNotSupported?.call();
      return [];
    }

    final isGranted = await requestPermissions();
    if (!isGranted) {
      isDeviceScanningNotifier.value = false;
      onPermissionsNotGranted?.call();
      return [];
    }

    if (await isBluetoothOn()) {
      isDeviceScanningNotifier.value = true;
      final devices = await _ble.startScanDevices(null);
      isDeviceScanningNotifier.value = false;
      return devices;
    } else {
      isDeviceScanningNotifier.value = false;
      await FlutterBluePlus.turnOn();
      final bleState = await FlutterBluePlus.adapterState.last;
      final isOn = bleState == BluetoothAdapterState.on;
      if (Platform.isIOS) {
        onBluetoothOffIos?.call();
      } else if (Platform.isAndroid && !isOn) {
        onBluetoothOffAndroid?.call();
      }
      return [];
    }
  }

  Future<bool> tryConnectToDevice(YuchengDevice device) async {
    try {
      selectedDeviceNotifier.value = device;
      isDeviceConnectedNotifier.value =
          await _ble.connect(selectedDeviceNotifier.value!);
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
      selectedDeviceNotifier.value = null;
      isDeviceConnectedNotifier.value = false;
      isReconnectedNotifier.value = false;
    } catch (e) {
      rethrow;
    }
  }

  Future<YuchengDevice?> getCurrentConnectedDevice() async {
    try {
      selectedDeviceNotifier.value = await _ble.getCurrentConnectedDevice();
      return selectedDevice;
    } catch (e) {
      rethrow;
    }
  }

  Future<YuchengDeviceSettings?> getDeviceSettings() async {
    try {
      deviceSettingsNotifier.value = await _ble.getDeviceSettings();
      return deviceSettings;
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

  Future<bool> isBluetoothSupported() async {
    final isSupported = await FlutterBluePlus.isSupported;
    return isSupported;
  }

  Future<bool> isBluetoothOn() async {
    final bluetoothIsOnCompleter = Completer<bool>();
    Timer? bluetoothTimer;
    final sub = FlutterBluePlus.adapterState.listen(
      (event) {
        if (event == BluetoothAdapterState.on &&
            !bluetoothIsOnCompleter.isCompleted) {
          bluetoothTimer?.cancel();
          bluetoothIsOnCompleter.complete(true);
          return;
        }
        if (bluetoothIsOnCompleter.isCompleted) return;
        bluetoothTimer ??= Timer.periodic(
          const Duration(seconds: 1),
          (timer) {
            if (timer.tick >= 5) {
              timer.cancel();
              bluetoothIsOnCompleter.complete(false);
              return;
            }
          },
        );
      },
    );
    final isBluetoothOn = await bluetoothIsOnCompleter.future;
    await sub.cancel();

    return isBluetoothOn;
  }

  Future<bool> requestPermissions() async {
    final granted = (await [
      Permission.location,
      Permission.storage,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetooth,
    ].request())
        .values
        .any((e) => e.isGranted);

    return granted;
  }
}
