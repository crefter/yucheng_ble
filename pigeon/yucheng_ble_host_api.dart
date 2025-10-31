// Команда для генерации: fvm dart run pigeon --input pigeon/yucheng_ble_host_api.dart

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

class YuchengDeviceSettings {
  final int batteryValue;
  final String firmwareVersion;

  const YuchengDeviceSettings({
    required this.batteryValue,
    required this.firmwareVersion,
  });
}

// SLEEP DATA
enum YuchengSleepType {
  rem,
  deep,
  awake,
  light,
  unknown;
}

class YuchengSleepData {
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

  const YuchengSleepData({
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

class YuchengHealthData {
  final int heartValue; // heart rate value
  final int hrvValue; // HRV
  final int cvrrValue; // CVRR
  final int OOValue; // oxygen value
  final int stepValue; // number of steps
  final int DBPValue; // diastolic pressure
  final int tempIntValue; // integer part of temperature
  final int tempFloatValue; // decimal part of temperature
  final int startTimestamp; // starttimestamp
  final int SBPValue; // systolic blood pressure
  final int respiratoryRateValue; // respiratory rate value
  final int bodyFatIntValue; // body fat integer part
  final int bodyFatFloatValue; // body fat decimal part
  final int bloodSugarValue; // blood sugar*10 value

  const YuchengHealthData({
    required this.heartValue,
    required this.hrvValue,
    required this.cvrrValue,
    required this.OOValue,
    required this.stepValue,
    required this.DBPValue,
    required this.tempIntValue,
    required this.tempFloatValue,
    required this.startTimestamp,
    required this.SBPValue,
    required this.respiratoryRateValue,
    required this.bodyFatIntValue,
    required this.bodyFatFloatValue,
    required this.bloodSugarValue,
  });
}

class YuchengSportData {
  final int startTimeStamp;
  final int endTimeStamp;
  final int distance;
  final int steps;
  final int calories;

  const YuchengSportData({
    required this.startTimeStamp,
    required this.endTimeStamp,
    required this.distance,
    required this.steps,
    required this.calories,
  });
}

class YuchengHealthSportData {
  final List<YuchengHealthData> healthData;
  final List<YuchengSportData> sportData;

  const YuchengHealthSportData({
    required this.healthData,
    required this.sportData,
  });
}

class YuchengAllData {
  final List<YuchengSleepData> sleepData;
  final YuchengHealthSportData healthSportData;

  const YuchengAllData({
    required this.sleepData,
    required this.healthSportData,
  });
}

sealed class YuchengSleepEvent {
  const YuchengSleepEvent();
}

class YuchengSleepTimeOutEvent extends YuchengSleepEvent {
  final bool isTimeout;

  const YuchengSleepTimeOutEvent({
    required this.isTimeout,
  });
}

class YuchengSleepDataEvent extends YuchengSleepEvent {
  final YuchengSleepData sleepData;

  const YuchengSleepDataEvent({
    required this.sleepData,
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

enum YuchengDeviceState {
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

class YuchengDeviceStateTimeOutEvent extends YuchengDeviceStateEvent {
  final bool isTimeout;

  const YuchengDeviceStateTimeOutEvent({
    required this.isTimeout,
  });
}

class YuchengDeviceStateDataEvent extends YuchengDeviceStateEvent {
  final YuchengDeviceState state;

  const YuchengDeviceStateDataEvent({
    required this.state,
  });
}

class YuchengDeviceStateErrorEvent extends YuchengDeviceStateEvent {
  final YuchengDeviceState state;
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
  final bool isReconnected;

  const YuchengDevice({
    required this.index,
    required this.deviceName,
    required this.uuid,
    required this.isReconnected,
  });
}

sealed class YuchengDeviceEvent {
  const YuchengDeviceEvent();
}

class YuchengDeviceTimeOutEvent extends YuchengDeviceEvent {
  final bool isTimeout;

  const YuchengDeviceTimeOutEvent({
    required this.isTimeout,
  });
}

class YuchengDeviceDataEvent extends YuchengDeviceEvent {
  final int index;

  /// ДЛЯ ANDROID
  /// Нужен, чтобы подключиться к девайсу
  final String mac;

  /// Только IOS
  /// true - уже изначально подключен
  /// false - не был подключен изначально, нужно подключить
  final bool isReconnected;
  final String deviceName;

  const YuchengDeviceDataEvent({
    required this.index,
    required this.deviceName,
    required this.mac,
    required this.isReconnected,
  });
}

class YuchengDeviceCompleteEvent extends YuchengDeviceEvent {
  final bool completed;

  YuchengDeviceCompleteEvent({required this.completed});
}

sealed class YuchengHealthEvent {
  const YuchengHealthEvent();
}

class YuchengHealthDataEvent extends YuchengHealthEvent {
  final YuchengHealthSportData healthData;

  const YuchengHealthDataEvent({
    required this.healthData,
  });
}

class YuchengHealthErrorEvent extends YuchengHealthEvent {
  final String error;

  const YuchengHealthErrorEvent({
    required this.error,
  });
}

class YuchengHealthTimeOutEvent extends YuchengHealthEvent {
  final bool isTimeout;

  const YuchengHealthTimeOutEvent({
    required this.isTimeout,
  });
}

sealed class YuchengAllEvent {
  const YuchengAllEvent();
}

class YuchengAllDataEvent extends YuchengAllEvent {
  final YuchengAllData data;

  const YuchengAllDataEvent({
    required this.data,
  });
}

class YuchengAllErrorEvent extends YuchengAllEvent {
  final String error;

  const YuchengAllErrorEvent({
    required this.error,
  });
}

class YuchengAllTimeOutEvent extends YuchengAllEvent {
  final bool isTimeout;

  const YuchengAllTimeOutEvent({
    required this.isTimeout,
  });
}

// UPDATE
sealed class YuchengUpdateEvent {
  const YuchengUpdateEvent();
}

class YuchengUpdateStartEvent extends YuchengUpdateEvent {
  final int startTimestamp;

  const YuchengUpdateStartEvent({required this.startTimestamp});
}

class YuchengUpdateProgressEvent extends YuchengUpdateEvent {
  final double progress;

  const YuchengUpdateProgressEvent({
    required this.progress,
  });
}

class YuchengUpdateCompleteEvent extends YuchengUpdateEvent {
  final int completeTimestamp;

  const YuchengUpdateCompleteEvent({required this.completeTimestamp});
}

class YuchengUpdateErrorEvent extends YuchengUpdateEvent {
  final String error;

  const YuchengUpdateErrorEvent({
    required this.error,
  });
}

class RealTimeBloodPressure {
  final int dbp;
  final int sbp;

  const RealTimeBloodPressure({
    required this.dbp,
    required this.sbp,
  });
}

@HostApi()
abstract class YuchengHostApi {
  /// [scanTimeInMs] - сколько по времени сканировать (по умолчанию 3 секунды для ios и 10 для андройд)
  /// Прослушивать стрим devices
  ///
  /// Перед сканированием нужно проверить, включен ли bluetooth и запросить разрешения
  /// на bluetooth
  @async
  List<YuchengDevice> startScanDevices(double? scanTimeInSeconds);

  /// Работает для IOS, для андройд будет просто проверка, подключен ли какой-либо девайс к сдк
  /// [device] - девайс, который нужно проверить
  /// Проверяет, подключен ли данный девайс
  @async
  bool isDeviceConnected(YuchengDevice? device);

  /// Подключить девайс к сдк
  @async
  bool connect(YuchengDevice device, int? connectTimeInSeconds);

  @async
  bool reconnect(int? reconnectTimeInSeconds);

  /// Отключить девайс от сдк
  @async
  void disconnect();

  /// Запрос на получение данных о сне
  /// Можно также прослушивать стрим sleepData
  @async
  List<YuchengSleepData> getSleepData({
    int? startTimestamp,
    int? endTimestamp,
  });

  /// Возвращает текущий подключенный девайс
  @async
  YuchengDevice? getCurrentConnectedDevice();

  /// Возвращает данные о здоровье
  @async
  YuchengHealthSportData getHealthSportData({
    int? startTimestamp,
    int? endTimestamp,
  });

  /// Возвращает данные о сне и здоровье
  @async
  YuchengAllData getAllData({
    int? startTimestamp,
    int? endTimestamp,
  });

  /// Возвращает настроики девайса
  @async
  YuchengDeviceSettings? getDeviceSettings();

  /// Удаляет данные о сне
  @async
  bool deleteSleepData();

  /// Удаляет данные о здоровье
  @async
  bool deleteHealthSportData();

  /// Удаляет данные о сне и здоровье
  @async
  bool deleteAllData();

  /// Сброс устройства до заводских настроек
  @async
  bool resetToFactory();

  /// Обновление девайса
  @async
  bool updateFirmware(YuchengDevice device, String pathToFile);

  /// Вернет null, если не получилось получить интервал
  @async
  int? getHealthMonitorInterval();

  /// [interval] - 1-60 (минуты)
  /// true - успех
  /// false - не успех
  @async
  bool setHealthMonitorInterval(int interval);

  @async
  YuchengHealthSportData getRealTimeHealthRecord();

  @async
  int startMeasurementBloodOxygen();

  @async
  int startMeasurementHeart();

  @async
  RealTimeBloodPressure startMeasurementBloodPressure();
  @async
  bool stopMeasurementBloodOxygen();
  @async
  bool stopMeasurementBloodPressure();
  @async
  bool stopMeasurementHeart();
  @async
  bool calibrateBloodPressure(int sbp, int dbp);
}

@EventChannelApi()
abstract class YuchengStreamApi {
  /// Стрим девайсов
  YuchengDeviceEvent devices();

  /// Стрим данных о сне
  YuchengSleepEvent sleepData();

  /// Стрим состояний девайсов (подключен или другие)
  YuchengDeviceStateEvent deviceState();

  /// Стрим данных о здоровье
  YuchengHealthEvent healthData();

  /// Стрим данных о сне и здоровье
  YuchengAllEvent allData();

  /// Стрим данных об обновлении
  YuchengUpdateEvent updateData();
}
