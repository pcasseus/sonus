/// "September 20–26, 2026" for a chart week, read in local dates like the
/// week picker and ChartWeekResolver, whose weeks start at local Sunday
/// midnight (SN-50 C-30). Stored week bounds are never changed.
///
/// [toLocal] turns a stored instant into local wall-clock fields; tests
/// pass a fixed zone.
String chartWeekLabel(
  DateTime weekStartUtc,
  DateTime weekEndUtc, {
  DateTime Function(DateTime instant)? toLocal,
}) {
  final local = toLocal ?? (DateTime instant) => instant.toLocal();
  final start = local(weekStartUtc);
  final end = local(weekEndUtc);
  final inclusiveEnd = DateTime.utc(end.year, end.month, end.day - 1);

  if (start.year == inclusiveEnd.year && start.month == inclusiveEnd.month) {
    return '${_monthName(start.month)} '
        '${start.day}–${inclusiveEnd.day}, '
        '${start.year}';
  }

  if (start.year == inclusiveEnd.year) {
    return '${_monthName(start.month)} ${start.day} – '
        '${_monthName(inclusiveEnd.month)} ${inclusiveEnd.day}, '
        '${start.year}';
  }

  return '${_monthName(start.month)} ${start.day}, ${start.year} – '
      '${_monthName(inclusiveEnd.month)} '
      '${inclusiveEnd.day}, ${inclusiveEnd.year}';
}

/// "Sep 20, 2026": a short local date, as for a debut week.
String chartShortDate(
  DateTime instant, {
  DateTime Function(DateTime instant)? toLocal,
}) {
  final local = (toLocal ?? (DateTime value) => value.toLocal())(instant);
  return '${_monthName(local.month).substring(0, 3)} ${local.day}, '
      '${local.year}';
}

String _monthName(int month) {
  return const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][month - 1];
}
