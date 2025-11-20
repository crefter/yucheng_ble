sealed class YuchengRealtimeDataResult {
  const YuchengRealtimeDataResult();
}

class YuchengRealtimeDataSingleResult extends YuchengRealtimeDataResult {
  final num value;

  const YuchengRealtimeDataSingleResult({required this.value});
}

class YuchengRealtimeDataBloodPressureResult extends YuchengRealtimeDataResult {
  final int sbp;
  final int dbp;

  const YuchengRealtimeDataBloodPressureResult(
      {required this.sbp, required this.dbp});
}
