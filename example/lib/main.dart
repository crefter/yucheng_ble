import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:yucheng_ble/export.dart';

extension RingSleepDataDetailX on YuchengSleepDataDetail {
  String toJson() {
    return '{"startTime": "$startDate", "endDate": "$endDate", "duration": $duration, "type": "$type"}';
  }
}

extension RingSleepDataX on YuchengSleepDataEvent {
  String toJson() {
    return '{"start": "$startDate", "end": "$endDate",'
        ' "deepCount": $deepCount, "lightCount": $lightCount, "awakeCount": $awakeCount,'
        '"deepInSeconds": $deepInSeconds, "lightInSeconds": $lightInSeconds, "awakeInSeconds": $awakeInSeconds, "remInSeconds": $remInSeconds,'
        '"details":'
        '${details.map((e) => e.toJson()).toList()}}';
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _ble = YuchengBle();
  late final StreamSubscription<YuchengDeviceEvent> devicesSub;
  late final StreamSubscription<YuchengSleepEvent> sleepDataSub;
  late final StreamSubscription<YuchengDeviceStateEvent> deviceStateSub;
  final List<YuchengDeviceEvent> devices = [];
  final List<YuchengSleepDataEvent> sleepData = [];
  final List<YuchengDeviceStateEvent> productState = [];
  bool isDeviceScanning = false;
  YuchengDevice? selectedDevice;
  bool isDeviceConnected = false;

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
        if (event is YuchengDeviceCompleteEvent) {
          if (!context.mounted) return;
          _showSnackBar(context, 'Конец сканирования');
          setState(() {
            isDeviceScanning = false;
          });
          return;
        }
        setState(() {
          devices.add(event);
        });
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
        if (event is YuchengSleepDataEvent) {
          print(event.toJson());
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

    deviceStateSub = _ble.deviceStateStream().listen(
      (event) {
        if (event is YuchengDeviceStateDataEvent) {
          if (event.state == YuchengProductState.readWriteOK) {
            isDeviceConnected = true;
          }
          setState(() {
            productState.add(event);
          });
          print('PRODUCT STATE = $event');
        } else if (event is YuchengDeviceStateErrorEvent) {
          if (!context.mounted) return;
          _showSnackBar(context, 'Ошибка: ${event.error}');
        }
      },
      onError: (e) {
        print('Error: Product state: $e');
      },
      onDone: () {
        print("PRODUCT STATE IS DONE");
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!Platform.isIOS) {
      _ble.reconnect().then((val) {
        print("RECONNECTED!!!!! - $val");
      });
    }
  }

  @override
  void dispose() {
    devicesSub.cancel();
    sleepDataSub.cancel();
    deviceStateSub.cancel();
    super.dispose();
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
            SliverToBoxAdapter(
              child: Text(
                'Hello, dear!',
                textAlign: TextAlign.center,
              ),
            ),
            SliverToBoxAdapter(
              child: TextButton(
                onPressed: () async {
                  devices.clear();
                  if (await FlutterBluePlus.adapterState.first ==
                      BluetoothAdapterState.on) {
                    final isGranted = await requestPermissions();
                    if (!isGranted) {
                      if (!context.mounted) return;
                      setState(() {
                        isDeviceScanning = false;
                      });
                      _showSnackBar(context, 'Не выдал разрешения(');
                    }
                    setState(() {
                      isDeviceScanning = true;
                    });
                    _ble.startScanDevices(null);
                  } else {
                    if (!context.mounted) return;
                    setState(() {
                      isDeviceScanning = false;
                    });
                    await FlutterBluePlus.turnOn();
                    _showSnackBar(context, 'Включи блютуз)');
                  }
                },
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
                final event = devices[index] as YuchengDeviceDataEvent;
                final deviceName = event.deviceName;
                final mac = event.mac;

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
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.red.shade200,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Text('Index: $index'),
                            const Gap(width: 12),
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
                );
              },
              separatorBuilder: (BuildContext context, int index) {
                return SizedBox(height: 8);
              },
            ),
            SliverList.separated(
              itemCount: productState.length,
              itemBuilder: (context, index) {
                final event = productState[index];

                final text = switch (event) {
                  YuchengDeviceStateDataEvent() => event.state.name,
                  YuchengDeviceStateErrorEvent() =>
                    '${event.state.name} - ${event.error}',
                };

                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.shade400,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(text),
                      ),
                    ],
                  ),
                );
              },
              separatorBuilder: (context, index) {
                return Gap(height: 10);
              },
            ),
            SliverToBoxAdapter(
              child: Builder(
                builder: (context) {
                  if (selectedDevice == null) return const SizedBox();

                  return Column(
                    children: [
                      const Gap(height: 10),
                      Text(
                        'Ты выбрал девайс: ${selectedDevice?.deviceName} : ${selectedDevice?.uuid}',
                      ),
                      const Gap(height: 10),
                      ElevatedButton(
                        onPressed: () async {
                          try {
                            isDeviceConnected =
                                await _ble.connect(selectedDevice!);
                            if (!context.mounted) return;
                            if (isDeviceConnected) {
                              _showSnackBar(context, 'Подключился!');
                            }
                            setState(() {});
                          } catch (e) {
                            if (!context.mounted) return;
                            _showSnackBar(
                              context,
                              'Не удалось подключиться( ${e.toString()}',
                            );
                          }
                        },
                        child: Text('Попробовать подключиться к девайсу'),
                      ),
                    ],
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: Builder(
                builder: (context) {
                  if (!isDeviceConnected) return const SizedBox();

                  return Column(
                    children: [
                      const Gap(height: 10),
                      ElevatedButton(
                        onPressed: () async {
                          try {
                            final data = await _ble.getSleepData();
                            final onlySleepData =
                                data.whereType<YuchengSleepDataEvent>();
                            setState(() {
                              sleepData.addAll(onlySleepData);
                            });
                            print(data);
                          } catch (e) {
                            if (!context.mounted) return;
                            _showSnackBar(context, 'Ошибка: ${e.toString()}');
                          }
                        },
                        child: Text('Получить данные о сне'),
                      ),
                    ],
                  );
                },
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 12),
              sliver: SliverList.separated(
                itemCount: sleepData.length,
                itemBuilder: (context, index) {
                  final item = sleepData[index];
                  final json = item.toJson();
                  return DecoratedBox(
                    decoration: BoxDecoration(color: Colors.green.shade500),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(json),
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

class Gap extends StatelessWidget {
  const Gap({
    super.key,
    this.height,
    this.width,
  });

  final double? height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: width,
    );
  }
}
