import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:yucheng_ble/export.dart';

extension SleepTypeX on YuchengSleepType {
  ({int r, int g, int b}) toColor() => switch (this) {
        YuchengSleepType.rem => (
            r: 123,
            g: 40,
            b: 45,
          ),
        YuchengSleepType.deep => (
            r: 65,
            g: 103,
            b: 75,
          ),
        YuchengSleepType.awake => (
            r: 89,
            g: 12,
            b: 174,
          ),
        YuchengSleepType.light => (
            r: 20,
            g: 190,
            b: 30,
          ),
        YuchengSleepType.unknown => (
            r: 100,
            g: 100,
            b: 100,
          ),
      };

  String get name => switch (this) {
        YuchengSleepType.rem => 'REM',
        YuchengSleepType.deep => 'Глубокий',
        YuchengSleepType.awake => 'Awake',
        YuchengSleepType.light => 'Легкий',
        YuchengSleepType.unknown => 'Неизвестный',
      };
}

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const YuchengSdkScreen(),
    );
  }
}

class YuchengSdkScreen extends StatefulWidget {
  const YuchengSdkScreen({super.key});

  @override
  State<YuchengSdkScreen> createState() => _YuchengSdkScreenState();
}

class _YuchengSdkScreenState extends State<YuchengSdkScreen> {
  final _ble = YuchengBle();
  late final StreamSubscription<YuchengDeviceEvent> devicesSub;
  late final StreamSubscription<YuchengSleepEvent> sleepDataSub;
  late final StreamSubscription<YuchengDeviceStateEvent> deviceStateSub;
  late final StreamSubscription<YuchengHealthEvent> healthSub;
  late final StreamSubscription<YuchengSleepHealthEvent> sleepHealthSub;
  late final StreamSubscription<BluetoothAdapterState> bluetoothStateSub;
  final List<YuchengDevice> devices = [];
  final List<YuchengSleepData> sleepData = [];
  final List<YuchengHealthData> healthData = [];
  final List<YuchengSleepHealthData> sleepHealthData = [];
  final List<YuchengDeviceStateEvent> deviceState = [];
  bool isDeviceScanning = false;
  YuchengDevice? selectedDevice;
  bool isDeviceConnected = false;
  bool isReconnected = false;

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

  @override
  void initState() {
    super.initState();

    devicesSub = _ble.devicesStream().listen(
      (event) {
        if (event is YuchengDeviceTimeOutEvent) {
          if (!context.mounted) return;
          _showSnackBar(context, 'Таймаут соединения');
        } else if (event is YuchengDeviceCompleteEvent) {
          if (!context.mounted) return;
          _showSnackBar(context, 'Конец сканирования');
          setState(() {
            isDeviceScanning = false;
          });
          return;
        }
        print(event);
      },
      onError: (e) {
        print('Error: Devices: $e');
      },
      onDone: () {
        print("DEVICES IS DONE");
      },
    );

    sleepDataSub = _ble.sleepDataStream().listen(
      (event) {
        if (event is YuchengSleepTimeOutEvent) {
          if (!context.mounted) return;
          _showSnackBar(context, 'Таймаут соединения');
        } else if (event is YuchengSleepDataEvent) {
          final json = event.sleepData.toJson();
          final str = jsonEncode(json);
          print(str);
        } else if (event is YuchengSleepErrorEvent) {
          if (!context.mounted) return;
          _showSnackBar(context, 'Ошибка: ${event.error}');
        }
      },
      onError: (e) {
        print('Error: Sleep data: $e');
      },
      onDone: () {
        print("SLEEP DATA IS DONE");
      },
    );

    healthSub = _ble.healthDataStream().listen(
      (event) {
        if (event is YuchengHealthTimeOutEvent) {
          if (!context.mounted) return;
          _showSnackBar(context, 'Таймаут соединения');
        } else if (event is YuchengHealthDataEvent) {
          final json = event.healthData.toJson();
          final str = jsonEncode(json);
          print(str);
        } else if (event is YuchengHealthErrorEvent) {
          if (!context.mounted) return;
          _showSnackBar(context, 'Ошибка: ${event.error}');
        }
      },
    );

    sleepHealthSub = _ble.sleepHealthDataStream().listen(
      (event) {
        if (event is YuchengSleepHealthTimeOutEvent) {
          if (!context.mounted) return;
          _showSnackBar(context, 'Таймаут соединения');
        } else if (event is YuchengSleepHealthDataEvent) {
          final json = event.data.toJson();
          final str = jsonEncode(json);
          print(str);
        } else if (event is YuchengSleepHealthErrorEvent) {
          if (!context.mounted) return;
          _showSnackBar(context, 'Ошибка: ${event.error}');
        }
      },
    );

    deviceStateSub = _ble.deviceStateStream().listen(
      (event) {
        if (event is YuchengDeviceStateTimeOutEvent) {
          if (!context.mounted) return;
          _showSnackBar(context, 'Таймаут соединения');
          setState(() {
            isDeviceConnected = false;
          });
        } else if (event is YuchengDeviceStateDataEvent) {
          if (event.state == YuchengDeviceState.readWriteOK) {
            isDeviceConnected = true;
          }
          setState(() {
            deviceState.add(event);
          });
          print('PRODUCT STATE = $event');
        } else if (event is YuchengDeviceStateErrorEvent) {
          if (!context.mounted) return;
          _showSnackBar(context, 'Ошибка: ${event.error}');
          setState(() {
            isDeviceConnected = false;
          });
        }
      },
      onError: (e) {
        print('Error: Product state: $e');
      },
      onDone: () {
        print("PRODUCT STATE IS DONE");
      },
    );

    bluetoothStateSub = FlutterBluePlus.adapterState.listen(
      (event) async {
        // Тут должна быть проверка на девайс, чтобы этот листенер работал только для реконнекта
        if (event == BluetoothAdapterState.on) {
          final isSupported = await _isBluetoothSupported();
          if (!isSupported) return;

          final isGranted = await requestPermissions();
          if (!isGranted) {
            if (!context.mounted) return;
            setState(() {
              isDeviceScanning = false;
            });
            _showSnackBar(context, 'Необходимо выдать разрешения!');
            return;
          }
          await tryReconnect();
        } else if (event == BluetoothAdapterState.off) {
          if (!context.mounted) return;
          _showSnackBar(context, 'Включи блутуз для работы с девайсом');
        }
      },
    );
  }

  @override
  void dispose() {
    devicesSub.cancel();
    sleepDataSub.cancel();
    deviceStateSub.cancel();
    bluetoothStateSub.cancel();
    super.dispose();
  }

  Future<bool> _isBluetoothSupported() async {
    final isSupported = await FlutterBluePlus.isSupported;
    if (!isSupported) {
      if (!context.mounted) return isSupported;
      _showSnackBar(context, 'Нет поддержки блютуз');
    }
    return isSupported;
  }

  Future<bool> _isBluetoothOn() async {
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

  Future<void> tryReconnect() async {
    final isBluetoothSupported = await _isBluetoothSupported();
    if (!isBluetoothSupported) return;

    final isGranted = await requestPermissions();
    if (!isGranted) {
      if (!context.mounted) return;
      setState(() {
        isDeviceScanning = false;
      });
      _showSnackBar(context, 'Необходимо выдать разрешения!');
      return;
    }

    if (!Platform.isIOS) {
      final isBleReconnected = await _ble.reconnect();
      if (isReconnected || isDeviceConnected) return;
      setState(() {
        isReconnected = isBleReconnected;
        isDeviceConnected = isBleReconnected;
      });
      print('RECONNECTED!!!!! - $isBleReconnected');
    } else {
      final isBleReconnect = await _ble.isDeviceConnected(null);
      if (isReconnected || isDeviceConnected) return;
      setState(() {
        isReconnected = isBleReconnect;
        isDeviceConnected = isBleReconnect;
      });
      print('RECONNECTED!!!!! - $isBleReconnect');
    }
  }

  Future<void> scanDevices() async {
    final isSupported = await _isBluetoothSupported();
    if (!isSupported) return;

    final isGranted = await requestPermissions();
    if (!isGranted) {
      if (!context.mounted) return;
      setState(() {
        isDeviceScanning = false;
      });
      _showSnackBar(context, 'Необходимо выдать разрешения!');
      return;
    }

    if (await _isBluetoothOn()) {
      setState(() {
        isDeviceScanning = true;
      });
      final devices = await _ble.startScanDevices(null);
      this.devices.clear();
      setState(() {
        this.devices.addAll(devices);
      });
    } else {
      if (!context.mounted) return;
      setState(() {
        isDeviceScanning = false;
      });
      await FlutterBluePlus.turnOn();
      final bleState = await FlutterBluePlus.adapterState.last;
      final isOn = bleState == BluetoothAdapterState.on;
      if (!context.mounted) return;
      if (Platform.isIOS) {
        _showSnackBar(
            context, 'Включи блютуз вручную и попробуй сканировать еще раз');
      } else if (Platform.isAndroid && !isOn) {
        _showSnackBar(context, 'Включи блютуз и попробуй сканировать еще раз');
      }
    }
  }

  Future<void> tryConnectToDevice() async {
    try {
      final isDeviceConnected = await _ble.connect(selectedDevice!);
      if (!context.mounted) return;
      this.isDeviceConnected = isDeviceConnected;
      if (isDeviceConnected) {
        _showSnackBar(context, 'Подключился!');
      } else {
        _showSnackBar(
            context, 'Не удалось подключиться почему-то, попробуй еще раз');
      }
      setState(() {});
    } catch (e) {
      if (!context.mounted) return;
      _showSnackBar(
        context,
        'Не удалось подключиться( ${e.toString()}',
      );
    }
  }

  Future<void> tryGetSleepData() async {
    try {
      final data = await _ble.getSleepData();
      setState(() {
        sleepData.clear();
        sleepData.addAll(data);
      });
      print(data);
    } catch (e) {
      if (!context.mounted) return;
      _showSnackBar(context, 'Ошибка: ${e}');
    }
  }

  Future<void> tryGetHealthData() async {
    try {
      final data = await _ble.getHealthData();
      setState(() {
        healthData.clear();
        healthData.addAll(data);
      });
      print(data);
    } catch (e) {
      if (!context.mounted) return;
      _showSnackBar(context, 'Ошибка: ${e}');
    }
  }

  Future<void> tryGetSleepHealthData() async {
    try {
      final data = await _ble.getSleepHealthData();
      setState(() {
        sleepHealthData.clear();
        sleepData
          ..clear()
          ..addAll(data.sleepData);

        healthData
          ..clear()
          ..addAll(data.healthData);

        sleepHealthData.add(data);
      });
      print(data);
    } catch (e) {
      if (!context.mounted) return;
      _showSnackBar(context, 'Ошибка: ${e}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: Text(
                'Hello, dear!',
                textAlign: TextAlign.center,
              ),
            ),
            if (isReconnected || isDeviceConnected)
              SliverToBoxAdapter(
                child: TextButton(
                  onPressed: () async {
                    final device = await _ble.getCurrentConnectedDevice();
                    print(device);
                  },
                  child: Text("Получить данные о текущем девайсе"),
                ),
              ),
            SliverToBoxAdapter(
              child: TextButton(
                onPressed: scanDevices,
                child: Text(
                  isDeviceScanning
                      ? 'Идет сканирование'
                      : 'Начать сканировать девайсов',
                ),
              ),
            ),
            SliverList.separated(
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final event = devices[index];
                final deviceName = event.deviceName;
                final mac = event.uuid;

                return Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        selectedDevice = YuchengDevice(
                          index: event.index,
                          uuid: mac,
                          deviceName: deviceName,
                          isCurrentConnected: false,
                        );
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _DecoratedItem(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              Text('Index: $index'),
                              const SizedBox(height: 10),
                              Column(
                                children: [
                                  Text('Device name: $deviceName'),
                                  const SizedBox(
                                    height: 8,
                                  ),
                                  Text('Mac address: $mac'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
              separatorBuilder: (context, index) {
                return const SizedBox(height: 8);
              },
            ),
            const SliverPadding(
              padding: EdgeInsets.symmetric(vertical: 12),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Состояния девайса: ',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            SliverList.separated(
              itemCount: deviceState.length,
              itemBuilder: (context, index) {
                final event = deviceState[index];

                final text = switch (event) {
                  YuchengDeviceStateDataEvent() => event.state.name,
                  YuchengDeviceStateErrorEvent() =>
                    '${event.state.name} - ${event.error}',
                  YuchengDeviceStateTimeOutEvent() => 'Time out to listen!',
                };

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _DecoratedItem(
                    child: Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(text),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              separatorBuilder: (context, index) {
                return const SizedBox(height: 10);
              },
            ),
            if (!isReconnected && selectedDevice != null)
              SliverToBoxAdapter(
                child: Builder(
                  builder: (context) {
                    return Column(
                      children: [
                        const SizedBox(height: 10),
                        Text(
                          'Ты выбрал девайс: ${selectedDevice?.deviceName} : ${selectedDevice?.uuid}',
                        ),
                        const SizedBox(height: 10),
                        if (!isDeviceConnected)
                          ElevatedButton(
                            onPressed: tryConnectToDevice,
                            child: const Text(
                                'Попробовать подключиться к девайсу'),
                          ),
                      ],
                    );
                  },
                ),
              ),
            SliverToBoxAdapter(
              child: Builder(
                builder: (context) {
                  if (!(isDeviceConnected || isReconnected)) {
                    return const SizedBox();
                  }

                  return Column(
                    children: [
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: tryGetSleepData,
                        child: const Text('Получить данные о сне'),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: tryGetHealthData,
                        child: const Text('Получить данные о здоровье'),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: tryGetSleepHealthData,
                        child: const Text('Получить данные о сне и здоровье'),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (healthData.isNotEmpty)
              const SliverPadding(
                padding: EdgeInsets.symmetric(vertical: 12),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'Данные о здоровье:',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 12),
              sliver: SliverList.separated(
                itemCount: healthData.length,
                itemBuilder: (context, index) {
                  final item = healthData[index];
                  return DecoratedBox(
                    decoration: const BoxDecoration(color: Colors.blueGrey),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Expanded(
                              child: Text(
                                'Дата: ${item.startDate}',
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Кислород: ${item.OOValue}',
                        ),
                        Text(
                          'Шаги: ${item.stepValue}',
                        ),
                        Text(
                          'Пульс: ${item.heartValue}',
                        ),
                      ],
                    ),
                  );
                },
                separatorBuilder: (context, index) {
                  return const SizedBox(height: 8);
                },
              ),
            ),
            if (sleepData.isNotEmpty)
              const SliverPadding(
                padding: EdgeInsets.symmetric(vertical: 12),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'Данные о сне:',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 12),
              sliver: SliverList.separated(
                itemCount: sleepData.length,
                itemBuilder: (context, index) {
                  final item = sleepData[index];
                  return DecoratedBox(
                    decoration: const BoxDecoration(color: Colors.black12),
                    child: ExpansionTile(
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Expanded(
                                child: Text(
                                  'Начало сна: ${item.startDate}\nКонец сна: ${item.endDate}',
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Легкий: ${item.lightInSeconds ~/ 60} мин.',
                          ),
                          Text(
                            'REM: ${item.remInSeconds ~/ 60} мин.',
                          ),
                          Text(
                            'Глубокий: ${item.deepInSeconds ~/ 60} мин.',
                          ),
                          Text(
                            'Awake: ${item.awakeInSeconds ~/ 60} мин.',
                          ),
                        ],
                      ),
                      children: item.details
                          .map((e) => Padding(
                                padding: const EdgeInsets.all(4),
                                child: _DetailItem(detail: e),
                              ))
                          .toList(),
                    ),
                  );
                },
                separatorBuilder: (context, index) {
                  return const SizedBox(height: 8);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          text,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  final YuchengSleepDataDetail detail;

  const _DetailItem({
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final type = detail.type;
    final end = detail.endDate;
    final start = detail.startDate;
    final duration = detail.duration ~/ 60;

    final color = type.toColor();

    return SizedBox(
      height: 40,
      child: DecoratedBox(
        decoration: BoxDecoration(
            color: Color.fromARGB(255, color.r, color.g, color.b)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Text(
                'Тип: ${type.name}, Длительность: $duration мин., Начало: $start, Конец: $end',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DecoratedItem extends StatelessWidget {
  const _DecoratedItem({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}
