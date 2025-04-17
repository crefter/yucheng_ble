import 'package:yucheng_ble/src/yucheng_ble.g.dart';

extension YuchengSleepTypeJson on YuchengSleepType {
  String get json => name;
}

extension YuchengSleepDataDetailJson on YuchengSleepDataDetail {
  Map<String, dynamic> toJson() {
    return {
      "startDate": startDate.toIso8601String(),
      "endDate": endDate.toIso8601String(),
      "duration": duration,
      "type": type.json,
    };
  }
}

extension YuchengSleepDataJson on YuchengSleepData {
  Map<String, dynamic> toJson() {
    return {
      "startDate": startDate.toIso8601String(),
      "endDate": endDate.toIso8601String(),
      "deepCount": deepCount,
      "lightCount": lightCount,
      "awakeCount": awakeCount,
      "deepInSeconds": deepInSeconds,
      "lightInSeconds": lightInSeconds,
      "awakeInSeconds": awakeInSeconds,
      "remInSeconds": remInSeconds,
      "details": details.map((e) => e.toJson()).toList(),
    };
  }
}

extension YuchengHealthDataJson on YuchengHealthData {
  Map<String, dynamic> toJson() {
    return {
      "heartValue": heartValue,
      "hrvValue": hrvValue,
      "cvrrValue": cvrrValue,
      "oxygenValue": OOValue,
      "stepValue": stepValue,
      "DBPValue": DBPValue,
      "tempIntValue": tempIntValue,
      "tempFloatValue": tempFloatValue,
      "startDate": startDate.toIso8601String(),
      "SBPValue": SBPValue,
      "respiratoryRateValue": respiratoryRateValue,
      "bodyFatIntValue": bodyFatIntValue,
      "bodyFatFloatValue": bodyFatFloatValue,
      "bloodSugarValue": bloodSugarValue,
    };
  }
}

extension YuchengSleepHealthDataX on YuchengSleepHealthData {
  Map<String, dynamic> toJson() {
    return {
      "sleepData": this.sleepData.map((e) => e.toJson()).toList(),
      "healthData": this.healthData.map((e) => e.toJson()).toList(),
    };
  }
}

extension YuchengSleepDataEventX on YuchengSleepData {
  DateTime get startDate {
    final startInMs = _timeStampInMs(startTimeStamp);
    return DateTime.fromMillisecondsSinceEpoch(startInMs);
  }

  DateTime get endDate {
    final endInMs = _timeStampInMs(endTimeStamp);
    return DateTime.fromMillisecondsSinceEpoch(endInMs);
  }

  int _timeStampInMs(int timeStamp) {
    final isMs = timeStamp.toString().length == 13;
    final timeStampInMs = isMs ? timeStamp : timeStamp * 1000;
    return timeStampInMs;
  }
}

extension YuchengSleepDataDetailX on YuchengSleepDataDetail {
  DateTime get startDate {
    final timeStampInMs = _timeStampInMs;
    return DateTime.fromMillisecondsSinceEpoch(
      timeStampInMs,
    );
  }

  DateTime get endDate {
    final timeStampInMs = _timeStampInMs;
    return DateTime.fromMillisecondsSinceEpoch(
        timeStampInMs + (duration * 1000));
  }

  int get _timeStampInMs {
    final isMs = startTimeStamp.toString().length == 13;
    final timeStampInMs = isMs ? startTimeStamp : startTimeStamp * 1000;
    return timeStampInMs;
  }
}

extension YuchengHealthDataX on YuchengHealthData {
  DateTime get startDate {
    final startInMs = _timeStampInMs;
    return DateTime.fromMillisecondsSinceEpoch(startInMs);
  }

  int get _timeStampInMs {
    final isMs = startTimestamp.toString().length == 13;
    final timeStampInMs = isMs ? startTimestamp : startTimestamp * 1000;
    return timeStampInMs;
  }
}
