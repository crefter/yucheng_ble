import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

base mixin YuchengServiceBluetoothMixin {
  final _deviceInfo = DeviceInfoPlugin();
  StreamSubscription<BluetoothAdapterState>? _bluetoothStateSub;
  String? _deviceId;

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

  void listenBluetoothState(
    VoidCallback bleOn,
    VoidCallback bleOff,
  ) {
    _bluetoothStateSub?.cancel();
    _bluetoothStateSub = FlutterBluePlus.adapterState.listen(
      (event) async {
        if (event == BluetoothAdapterState.on) {
          bleOn();
        } else if (event == BluetoothAdapterState.off) {
          bleOff();
        }
      },
    );
  }

  void cancelListenBluetoothState() => _bluetoothStateSub?.cancel();

  Future<bool> isBluetoothSupported() async {
    final isSupported = await FlutterBluePlus.isSupported;
    return isSupported;
  }

  Future<bool> isBluetoothOn() async {
    final isOn = await FlutterBluePlus.adapterState.last;
    return isOn == BluetoothAdapterState.on;
  }

  Future<void> tryTurnOnBluetooth() async {
    await FlutterBluePlus.turnOn();
  }

  Future<bool> isBluetoothOnWithTimer() async {
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
            if (timer.tick >= 3) {
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
    final permissions = await _permissions;
    final granted =
        (await permissions.request()).values.any((e) => e.isGranted);

    return granted;
  }

  Future<bool> isPermissionsGranted() async {
    final permissions = await _permissions;
    final permissionsGranted =
        await [for (final permission in permissions) permission.isGranted].wait;
    return permissionsGranted.every((isGranted) => isGranted);
  }

  Future<String> getDeviceId() async {
    _deviceId ??= (Platform.isAndroid
        ? (await _deviceInfo.androidInfo).id
        : (await _deviceInfo.iosInfo).identifierForVendor);
    return _deviceId ?? '';
  }
}
