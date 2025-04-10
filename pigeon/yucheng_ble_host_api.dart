import 'package:pigeon/pigeon.dart';

// #docregion config
@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/yucheng_ble.g.dart',
  dartOptions: DartOptions(),
  kotlinOut:
      'android/src/main/kotlin/com/crefter/yuchengplugin/yucheng_ble/YuchengBleApi.g.kt',
  kotlinOptions: KotlinOptions(),
  swiftOut: 'ios/Classes/YuchengBleApi.g.swift',
  swiftOptions: SwiftOptions(),
  dartPackageName: 'yucheng_ble',
))
// #enddocregion config

// SLEEP DATA
enum YuchengSleepType {
  rem,
  deep,
  awake,
  light,
  unknown;
}

sealed class YuchengSleepEvent {
  const YuchengSleepEvent();
}

class YuchengSleepDataEvent extends YuchengSleepEvent {
  /// Начало сна в мс
  final int startTimeStamp;

  /// Конец сна в мс
  final int endTimeStamp;

  /// Если равен 0xFFFF, то новый формат в секундах, иначе старый в минутах
  final int deepCount;

  final int lightCount;
  final int awakeCount;
  final int deepInSeconds;

  final int remInSeconds;
  final int lightInSeconds;
  final int awakeInSeconds;

  final List<YuchengSleepDataDetail> details;

  const YuchengSleepDataEvent({
    required this.startTimeStamp,
    required this.endTimeStamp,
    required this.deepCount,
    required this.awakeCount,
    required this.lightCount,
    required this.deepInSeconds,
    required this.remInSeconds,
    required this.lightInSeconds,
    required this.awakeInSeconds,
    required this.details,
  });
}

class YuchengSleepDataDetail {
  /// Начало в мс
  final int startTimeStamp;

  /// Длительность в мс
  final int duration;

  /// Тип сна
  final YuchengSleepType type;

  const YuchengSleepDataDetail({
    required this.startTimeStamp,
    required this.duration,
    required this.type,
  });
}

class YuchengSleepErrorEvent extends YuchengSleepEvent {
  final String error;

  const YuchengSleepErrorEvent({required this.error});
}

// PRODUCT

enum YuchengProductState {
  unknown,
  connected,
  connectedFailed,
  disconnected,
  unavailable,
  readWriteOK,
  timeOut;
}

sealed class YuchengDeviceStateEvent {
  const YuchengDeviceStateEvent();
}

class YuchengDeviceStateDataEvent extends YuchengDeviceStateEvent {
  final YuchengProductState state;

  const YuchengDeviceStateDataEvent({
    required this.state,
  });
}

class YuchengDeviceStateErrorEvent extends YuchengDeviceStateEvent {
  final YuchengProductState state;
  final String error;

  const YuchengDeviceStateErrorEvent({
    required this.state,
    required this.error,
  });
}

// DEVICE
class YuchengDevice {
  final int index;
  final String deviceName;

  /// Android - тут mac address для подключения
  /// IOS - uuid девайса
  final String uuid;

  /// true - уже изначально подключен
  /// false - не был подключен изначально, нужно подключить
  final bool isCurrentConnected;

  const YuchengDevice({
    required this.index,
    required this.deviceName,
    required this.uuid,
    required this.isCurrentConnected,
  });
}

sealed class YuchengDeviceEvent {
  const YuchengDeviceEvent();
}

class YuchengDeviceDataEvent extends YuchengDeviceEvent {
  final int index;

  /// ДЛЯ ANDROID
  /// Нужен, чтобы подключиться к девайсу
  /// ДЛЯ IOS
  /// Uuid девайса
  final String mac;

  /// Только IOS
  /// true - уже изначально подключен
  /// false - не был подключен изначально, нужно подключить
  final bool? isCurrentConnected;
  final String deviceName;

  const YuchengDeviceDataEvent({
    required this.index,
    required this.deviceName,
    required this.mac,
    required this.isCurrentConnected,
  });
}

class YuchengDeviceCompleteEvent extends YuchengDeviceEvent {
  final bool completed;

  YuchengDeviceCompleteEvent({required this.completed});
}

@HostApi()
abstract class YuchengHostApi {
  /// [scanTimeInMs] - сколько по времени сканировать (по умолчанию 3 секунды для ios и 10 для андройд)
  /// Прослушивать стрим devices
  ///
  /// Перед сканированием нужно проверить, включен ли bluetooth и запросить разрешения
  /// на bluetooth
  void startScanDevices(double? scanTimeInSeconds);

  /// Работает для IOS, для андройд будет просто проверка, подключен ли какой-либо девайс к сдк
  /// [device] - девайс, который нужно проверить
  /// Проверяет, подключен ли данный девайс
  @async
  bool isDeviceConnected(YuchengDevice? device);

  /// Подключить девайс к сдк
  @async
  bool connect(YuchengDevice device);

  @async
  bool reconnect();

  /// Отключить девайс от сдк
  @async
  void disconnect();

  /// Запрос на получение данных о сне
  /// Можно также прослушивать стрим sleepData
  @async
  List<YuchengSleepEvent?> getSleepData();

  /// ТОЛЬКО IOS
  /// Возвращает текущий подключенный девайс
  /// Если девайс был подключен до этого и не был отключен, то сдк пытается подключиться
  /// к девайсу повторно и возвращает его
  @async
  YuchengDevice? getCurrentConnectedDevice();
}

@EventChannelApi()
abstract class YuchengStreamApi {
  /// Стрим девайсов
  YuchengDeviceEvent devices();

  /// Стрим данных о сне
  YuchengSleepEvent sleepData();

  /// Стрим состояний девайсов (подключен или другие)
  YuchengDeviceStateEvent deviceState();
}
