import 'dart:async';
import 'dart:ui';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

base mixin YuchengServiceBluetoothMixin {
  late final StreamSubscription<BluetoothAdapterState> _bluetoothStateSub;

  void listenBluetoothState(
    VoidCallback bleOn,
    VoidCallback bleOff,
  ) {
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

  void cancelListenBluetoothState() => _bluetoothStateSub.cancel();

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
