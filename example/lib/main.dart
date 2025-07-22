import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
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
  final _service = YuchengService();
  final List<YuchengDevice> devices = [];
  final List<YuchengSleepData> sleepData = [];
  final List<YuchengHealthData> healthData = [];
  final List<YuchengSleepHealthData> sleepHealthData = [];
  YuchengDevice? selectedDevice;

  @override
  void initState() {
    super.initState();
    _service
      ..listenAll(() => setState(() {}))
      ..init(
        shouldTryReconnect: () async => true,
        onBluetoothNotSupported: () {
          if (!context.mounted) return;
          _showSnackBar(context, 'Блютуз не поддерживается!');
        },
        onPermissionsNotGranted: () {
          if (!context.mounted) return;
          _showSnackBar(context, 'Разрешения не выданы!');
        },
        onDeviceConnectedYet: () {
          if (!context.mounted) return;
          _showSnackBar(context, 'Девайс уже подключен!');
        },
        onBluetoothOff: () {
          if (!context.mounted) return;
          _showSnackBar(context, 'Включи блютуз!');
        },
        onSuccessfulReconnect: () {
          if (!context.mounted) return;
          _showSnackBar(context, 'Подключение установлено!');
        },
        onFailedReconnect: () {
          if (!context.mounted) return;
          _showSnackBar(context, 'Подключение не установлено!');
        },
      );
    _service.selectedDeviceNotifier.addListener(() {
      selectedDevice = _service.selectedDevice;
    });
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> scanDevices() async {
    final scannedDevices = await _service.scanDevices(
      onBluetoothNotSupported: () {
        if (!context.mounted) return;
        _showSnackBar(context, 'Блютуз не поддерживается!');
      },
      onPermissionsNotGranted: () {
        if (!context.mounted) return;
        _showSnackBar(context, 'Разрешения не выданы!');
      },
      onBluetoothOffIos: () {
        if (!context.mounted) return;
        _showSnackBar(context, 'Включи блютуз вручную!');
      },
      onBluetoothOffAndroid: () {
        if (!context.mounted) return;
        _showSnackBar(context, 'Включи блютуз вручную!');
      },
    );
    setState(() {
      devices.clear();
      devices.addAll(scannedDevices);
    });
  }

  Future<void> tryConnectToDevice() async {
    if (selectedDevice == null) return;
    await _service.tryConnectToDevice(selectedDevice!);
    setState(() {});
  }

  Future<void> tryGetSleepData() async {
    final data = await _service.tryGetSleepData();
    sleepData
      ..clear()
      ..addAll(data);
    setState(() {});
  }

  Future<void> tryGetHealthData() async {
    final data = await _service.tryGetHealthData();
    healthData
      ..clear()
      ..addAll(data);
    setState(() {});
  }

  Future<void> tryGetSleepHealthData() async {
    final data = await _service.tryGetSleepHealthData();
    sleepHealthData
      ..clear()
      ..add(data);
    sleepData
      ..clear()
      ..addAll(data.sleepData);
    healthData
      ..clear()
      ..addAll(data.healthData);
    setState(() {});
  }

  Future<void> getDeviceSettings() async {
    await _service.getDeviceSettings();
  }

  Future<bool> tryReconnect() async {
    return await _service.tryReconnect();
  }

  Future<bool> resetToFactory() async {
    return await _service.resetToFactory();
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
            SliverToBoxAdapter(
              child: ValueListenableBuilder(
                  valueListenable: _service.isDeviceConnectedNotifier,
                  builder: (context, isDeviceConnected, _) {
                    return ValueListenableBuilder(
                      valueListenable: _service.isReconnectedNotifier,
                      builder: (context, isReconnected, child) {
                        if (isReconnected || isDeviceConnected) {
                          return child!;
                        }

                        return const SizedBox.shrink();
                      },
                      child: ElevatedButton(
                        onPressed: () async {
                          final isReset = await resetToFactory();
                          if (isReset) {
                            sleepData.clear();
                            healthData.clear();
                            sleepHealthData.clear();
                          }
                          if (!context.mounted) return;
                          final text = isReset
                              ? 'Сброс ввыполнен! Попробуй переподключиться'
                              : 'Сброс не выполнен! ';
                          _showSnackBar(context, text);
                        },
                        child: Text('Сбросить настройки'),
                      ),
                    );
                  }),
            ),
            SliverToBoxAdapter(
              child: ValueListenableBuilder(
                valueListenable: _service.isReconnectedNotifier,
                builder: (context, isReconnected, child) {
                  if (isReconnected) {
                    return const Text(
                      'Переподключились!',
                      textAlign: TextAlign.center,
                    );
                  } else {
                    return child!;
                  }
                },
                child: ValueListenableBuilder(
                  valueListenable: _service.isReconnectingNotifier,
                  builder: (context, isReconnecting, child) {
                    if (isReconnecting) {
                      return const Column(
                        children: [
                          Text('Пробуем переподключиться...'),
                          CircularProgressIndicator(),
                        ],
                      );
                    } else {
                      return ElevatedButton(
                        onPressed: tryReconnect,
                        child: Text(
                          'Переподключиться',
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
            if (_service.isReconnected || _service.isAnyDeviceConnected)
              SliverToBoxAdapter(
                child: TextButton(
                  onPressed: () async {
                    final device = await _service.getCurrentConnectedDevice();
                    print(device);
                  },
                  child: const Text('Получить данные о текущем девайсе'),
                ),
              ),
            if (sleepHealthData.isNotEmpty)
              SliverToBoxAdapter(
                child: TextButton(
                  onPressed: () async {
                    final data = jsonEncode(sleepHealthData.first.toJson());
                    final deviceId = await _service.getDeviceId();
                    final json = '{'
                        '"device_id": "$deviceId",'
                        '"utc_offset": "${DateTime.now().timeZoneOffset.inMinutes}",'
                        '"data": $data'
                        '}';
                    if (!context.mounted) return;
                    await showAdaptiveDialog(
                      context: context,
                      builder: (context) {
                        return SimpleDialog(
                          backgroundColor: Colors.blue.shade300,
                          contentPadding: const EdgeInsets.all(12),
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                  },
                                  icon: const Icon(
                                    Icons.clear,
                                    size: 24,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              json,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        );
                      },
                    );
                  },
                  child: const Text(
                      'Сформировать json c данными о сне и здоровье'),
                ),
              ),
            if (_service.deviceSettings != null)
              SliverToBoxAdapter(
                child: TextButton(
                  onPressed: () async {
                    final data = jsonEncode(_service.deviceSettings!.toJson());
                    if (!context.mounted) return;
                    await showAdaptiveDialog(
                      context: context,
                      builder: (context) {
                        return SimpleDialog(
                          backgroundColor: Colors.blue.shade300,
                          contentPadding: const EdgeInsets.all(12),
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                  },
                                  icon: const Icon(
                                    Icons.clear,
                                    size: 24,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              data,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        );
                      },
                    );
                  },
                  child: const Text(
                      'Сформировать json c данными о настройках (уровне заряда)'),
                ),
              ),
            SliverToBoxAdapter(
              child: TextButton(
                onPressed: scanDevices,
                child: ValueListenableBuilder(
                  valueListenable: _service.isReconnectedNotifier,
                  builder: (context, isReconnected, child) {
                    if (isReconnected) {
                      return const SizedBox.shrink();
                    } else {
                      return child!;
                    }
                  },
                  child: ValueListenableBuilder(
                    valueListenable: _service.isDeviceScanningNotifier,
                    builder: (context, isDeviceScanning, _) {
                      return Text(
                        isDeviceScanning
                            ? 'Идет сканирвание'
                            : 'Начать сканирование',
                      );
                    },
                  ),
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
                        _service.selectedDeviceNotifier.value = YuchengDevice(
                          index: event.index,
                          uuid: mac,
                          deviceName: deviceName,
                          isReconnected: event.isReconnected,
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
            if (selectedDevice != null)
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
                        if (!_service.isAnyDeviceConnected)
                          ElevatedButton(
                            onPressed: tryConnectToDevice,
                            child: const Text(
                              'Попробовать подключиться к девайсу',
                            ),
                          )
                        else
                          ElevatedButton(
                            onPressed: () async {
                              await _service.disconnect();
                              healthData.clear();
                              sleepData.clear();
                              sleepHealthData.clear();
                              setState(() {});
                            },
                            child: const Text(
                              'Отключиться от девайса',
                            ),
                          ),
                        const SizedBox(height: 8),
                        if (_service.isAnyDeviceConnected) ...[
                          ElevatedButton(
                            onPressed: _service.deleteSleepData,
                            child: Text('Удалить данные о сне'),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _service.deleteHealthData,
                            child: Text('Удалить данные о здоровье'),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _service.deleteSleepHealthData,
                            child: Text('Удалить данные о сне и здоровье'),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            SliverToBoxAdapter(
              child: Builder(
                builder: (context) {
                  if (!(_service.isAnyDeviceConnected ||
                      _service.isReconnected)) {
                    return const SizedBox();
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: getDeviceSettings,
                          child: const Text(
                            'Получить данные о настройках (уровень заряда)',
                            textAlign: TextAlign.center,
                          ),
                        ),
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
                    ),
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
