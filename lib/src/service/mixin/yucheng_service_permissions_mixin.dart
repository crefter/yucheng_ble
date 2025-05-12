import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

base mixin YuchengServicePermissionsMixin {
  final _deviceInfo = DeviceInfoPlugin();
  String? _deviceId;

  Future<String> getDeviceId() async {
    _deviceId ??= (Platform.isAndroid
        ? (await _deviceInfo.androidInfo).id
        : (await _deviceInfo.iosInfo).identifierForVendor);
    return _deviceId ?? '';
  }

  Future<List<Permission>> get _permissions async {
    final p = [
      Permission.location,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetooth,
    ];
    if (Platform.isAndroid) {
      final androidVersion = (await _deviceInfo.androidInfo).version.sdkInt;
      if (androidVersion < 33) {
        p.add(Permission.storage);
      }
    } else if (Platform.isIOS) {
      p.add(Permission.storage);
    }
    return p;
  }

  Future<bool> requestPermissions() async {
    final permissions = await _permissions;
    final granted =
        (await permissions.request()).values.every((e) => e.isGranted);

    return granted;
  }

  Future<bool> isPermissionsGranted() async {
    final permissions = await _permissions;
    final permissionsGranted =
        await [for (final p in permissions) p.isGranted].wait;
    return permissionsGranted.every((isGranted) => isGranted);
  }

  Future<bool> isLocationPermanentlyDenied() async {
    final permission = Permission.location;
    return await permission.isPermanentlyDenied;
  }

  Future<bool> isBluetoothPermanentlyDenied() async {
    final permissions = [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetooth,
    ];
    final isAllDenied =
        await [for (final p in permissions) p.isPermanentlyDenied].wait;
    return isAllDenied.any((e) => e);
  }

  Future<bool> isPermissionsPermanentlyDenied() async {
    return await isLocationPermanentlyDenied() &&
        await isBluetoothPermanentlyDenied();
  }

  Future<bool> openSettings() => openAppSettings();
}
