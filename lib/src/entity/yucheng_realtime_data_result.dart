sealed class YuchengRealtimeDataResult {
  const YuchengRealtimeDataResult();
}

class YuchengRealtimeDataSingleResult {
  final num value;

  const YuchengRealtimeDataSingleResult({required this.value});
}

class YuchengRealtimeDataBloodPressureResult {
  final int sbp;
  final int dbp;

  const YuchengRealtimeDataBloodPressureResult(
      {required this.sbp, required this.dbp});
}
