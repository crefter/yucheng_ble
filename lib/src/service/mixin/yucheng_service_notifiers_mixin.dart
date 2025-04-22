import 'package:flutter/foundation.dart';
import 'package:yucheng_ble/src/yucheng_ble.g.dart';

base mixin YuchengServiceNotifiersMixin {
  bool wasDisposed = false;
  final ValueNotifier<YuchengDevice?> selectedDeviceNotifier =
      ValueNotifier(null);
  final ValueNotifier<YuchengDeviceSettings?> deviceSettingsNotifier =
      ValueNotifier(null);
  final ValueNotifier<bool> isDeviceScanningNotifier = ValueNotifier(false);
  final ValueNotifier<bool> isDeviceConnectedNotifier = ValueNotifier(false);
  final ValueNotifier<bool> isReconnectedNotifier = ValueNotifier(false);
  final ValueNotifier<bool> isReconnectingNotifier = ValueNotifier(false);

  bool get isDeviceScanning => isDeviceScanningNotifier.value;

  bool get isAnyDeviceConnected => isDeviceConnectedNotifier.value;

  bool get isReconnected => isReconnectedNotifier.value;

  bool get isReconnecting => isReconnectingNotifier.value;

  YuchengDevice? get selectedDevice => selectedDeviceNotifier.value;

  YuchengDeviceSettings? get deviceSettings => deviceSettingsNotifier.value;

  void listenDeviceScanning(VoidCallback callback) =>
      isDeviceScanningNotifier.addListener(callback);

  void cancelListenDeviceScanning(VoidCallback callback) =>
      isDeviceScanningNotifier.removeListener(callback);

  void listenDeviceConnected(VoidCallback callback) =>
      isDeviceConnectedNotifier.addListener(callback);

  void cancelListenDeviceConnected(VoidCallback callback) =>
      isDeviceConnectedNotifier.removeListener(callback);

  void listenReconnected(VoidCallback callback) =>
      isReconnectedNotifier.addListener(callback);

  void cancelListenReconnected(VoidCallback callback) =>
      isReconnectedNotifier.removeListener(callback);

  void listenReconnecting(VoidCallback callback) =>
      isReconnectingNotifier.addListener(callback);

  void cancelListenReconnecting(VoidCallback callback) =>
      isReconnectingNotifier.removeListener(callback);

  void listenSelectedDevice(VoidCallback callback) =>
      selectedDeviceNotifier.addListener(callback);

  void cancelListenSelectedDevice(VoidCallback callback) =>
      selectedDeviceNotifier.removeListener(callback);

  void listenDeviceSettings(VoidCallback callback) =>
      deviceSettingsNotifier.addListener(callback);

  void cancelListenDeviceSettings(VoidCallback callback) =>
      deviceSettingsNotifier.removeListener(callback);

  void setDeviceScanning(bool value) {
    if (wasDisposed) return;
    isDeviceScanningNotifier.value = value;
  }

  void setDeviceConnected(bool value) {
    if (wasDisposed) return;
    isDeviceConnectedNotifier.value = value;
  }

  void setReconnected(bool value) {
    if (wasDisposed) return;
    isReconnectedNotifier.value = value;
  }

  void setReconnecting(bool value) {
    if (wasDisposed) return;
    isReconnectingNotifier.value = value;
  }

  void setSelectedDevice(YuchengDevice? value) {
    if (wasDisposed) return;
    selectedDeviceNotifier.value = value;
  }

  void setDeviceSettings(YuchengDeviceSettings? value) {
    if (wasDisposed) return;
    deviceSettingsNotifier.value = value;
  }

  void listenAll(VoidCallback callback) {
    isDeviceScanningNotifier.addListener(callback);
    isReconnectedNotifier.addListener(callback);
    isDeviceConnectedNotifier.addListener(callback);
    selectedDeviceNotifier.addListener(callback);
    isReconnectingNotifier.addListener(callback);
    deviceSettingsNotifier.addListener(callback);
  }

  void cancelListenAll(VoidCallback callback) {
    isDeviceScanningNotifier.removeListener(callback);
    isReconnectedNotifier.removeListener(callback);
    isDeviceConnectedNotifier.removeListener(callback);
    selectedDeviceNotifier.removeListener(callback);
    isReconnectingNotifier.removeListener(callback);
    deviceSettingsNotifier.removeListener(callback);
  }

  void disposeNotifiers() {
    wasDisposed = true;
    isDeviceScanningNotifier.dispose();
    isReconnectedNotifier.dispose();
    isDeviceConnectedNotifier.dispose();
    selectedDeviceNotifier.dispose();
    isReconnectingNotifier.dispose();
    deviceSettingsNotifier.dispose();
  }
}
