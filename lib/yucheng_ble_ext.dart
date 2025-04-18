import 'package:yucheng_ble/src/yucheng_ble.g.dart';

extension YuchengSleepTypeJson on YuchengSleepType {
  String get json => name;
}

extension YuchengSleepDataDetailJson on YuchengSleepDataDetail {
  Map<String, dynamic> toJson() {
    return {
      "start_date": startDate.toIso8601String(),
      "end_date": endDate.toIso8601String(),
      "duration_in_seconds": duration,
      "type": type.json,
    };
  }
}

extension YuchengSleepDataJson on YuchengSleepData {
  Map<String, dynamic> toJson() {
    return {
      "start_date": startDate.toIso8601String(),
      "end_date": endDate.toIso8601String(),
      "deep_count": deepCount,
      "light_count": lightCount,
      "awake_count": awakeCount,
      "deep_in_seconds": deepInSeconds,
      "light_in_seconds": lightInSeconds,
      "awake_in_seconds": awakeInSeconds,
      "rem_in_seconds": remInSeconds,
      "details": details.map((e) => e.toJson()).toList(),
    };
  }
}

extension YuchengHealthDataJson on YuchengHealthData {
  Map<String, dynamic> toJson() {
    return {
      "heart_value": heartValue,
      "hrv_value": hrvValue,
      "cvrr_value": cvrrValue,
      "oxygen_value": OOValue,
      "step_value": stepValue,
      "dbp_value": DBPValue,
      "temp_int_value": tempIntValue,
      "temp_float_value": tempFloatValue,
      "start_date": startDate.toIso8601String(),
      "sbp_value": SBPValue,
      "respiratory_rate_value": respiratoryRateValue,
      "body_fat_int_value": bodyFatIntValue,
      "body_fat_float_value": bodyFatFloatValue,
      "blood_sugar_value": bloodSugarValue,
    };
  }
}

extension YuchengSleepHealthDataX on YuchengSleepHealthData {
  Map<String, dynamic> toJson() {
    return {
      "sleep_data": this.sleepData.map((e) => e.toJson()).toList(),
      "health_data": this.healthData.map((e) => e.toJson()).toList(),
    };
  }
}

extension YuchengDeviceSettingsJson on YuchengDeviceSettings {
  Map<String, dynamic> toJson() {
    return {
      "battery_value": batteryValue,
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
