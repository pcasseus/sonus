class AnalyticsTimeWindow {
  const AnalyticsTimeWindow({required this.startUtc, required this.endUtc});

  final DateTime? startUtc;
  final DateTime? endUtc;

  bool get isLifetime => startUtc == null && endUtc == null;

  bool contains(DateTime instant) {
    final utc = instant.toUtc();
    final start = startUtc;
    final end = endUtc;

    if (start != null && utc.isBefore(start)) {
      return false;
    }

    if (end != null && !utc.isBefore(end)) {
      return false;
    }

    return true;
  }
}
