class ChartWeek {
  const ChartWeek({required this.startUtc, required this.endUtc});

  final DateTime startUtc;
  final DateTime endUtc;

  bool contains(DateTime instant) {
    final utc = instant.toUtc();

    return !utc.isBefore(startUtc) && utc.isBefore(endUtc);
  }
}
