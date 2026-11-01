import '../analytics_time_window.dart';

/// The two Sonus Pulse views.
enum PulsePeriodKind { month, year }

/// One Sonus Pulse period: a calendar month or year in the device's current
/// time zone (decision 5: no per-play offset is stored, so plays are bucketed
/// by the zone the device is in now; the page explains this).
class PulsePeriod {
  const PulsePeriod._(this.kind, this.year, this.month);

  factory PulsePeriod.month(int year, int month) {
    final normalized = DateTime(year, month);
    return PulsePeriod._(
      PulsePeriodKind.month,
      normalized.year,
      normalized.month,
    );
  }

  factory PulsePeriod.year(int year) =>
      PulsePeriod._(PulsePeriodKind.year, year, 1);

  /// The period of [kind] containing [local].
  factory PulsePeriod.containing(PulsePeriodKind kind, DateTime local) =>
      switch (kind) {
        PulsePeriodKind.month => PulsePeriod.month(local.year, local.month),
        PulsePeriodKind.year => PulsePeriod.year(local.year),
      };

  final PulsePeriodKind kind;
  final int year;

  /// 1–12 for a month; 1 for a year.
  final int month;

  /// Local midnight on the first day.
  DateTime get startLocal => DateTime(year, month);

  /// Local midnight on the first day of the next period (exclusive).
  DateTime get endLocal => switch (kind) {
    PulsePeriodKind.month => DateTime(year, month + 1),
    PulsePeriodKind.year => DateTime(year + 1),
  };

  AnalyticsTimeWindow get window => AnalyticsTimeWindow(
    startUtc: startLocal.toUtc(),
    endUtc: endLocal.toUtc(),
  );

  /// Every local calendar day in the period, in order.
  List<DateTime> get days {
    final result = <DateTime>[];
    var day = startLocal;
    final end = endLocal;
    while (day.isBefore(end)) {
      result.add(day);
      day = DateTime(day.year, day.month, day.day + 1);
    }
    return List.unmodifiable(result);
  }

  /// The month before, or the year before.
  PulsePeriod get previous => switch (kind) {
    PulsePeriodKind.month => PulsePeriod.month(year, month - 1),
    PulsePeriodKind.year => PulsePeriod.year(year - 1),
  };

  /// The next month, or the next year.
  PulsePeriod get next => switch (kind) {
    PulsePeriodKind.month => PulsePeriod.month(year, month + 1),
    PulsePeriodKind.year => PulsePeriod.year(year + 1),
  };

  /// The same month a year earlier; for a year, the previous year.
  PulsePeriod get samePeriodLastYear => switch (kind) {
    PulsePeriodKind.month => PulsePeriod.month(year - 1, month),
    PulsePeriodKind.year => PulsePeriod.year(year - 1),
  };

  bool containsLocalDay(DateTime local) =>
      !local.isBefore(startLocal) && local.isBefore(endLocal);

  @override
  bool operator ==(Object other) =>
      other is PulsePeriod &&
      other.kind == kind &&
      other.year == year &&
      other.month == month;

  @override
  int get hashCode => Object.hash(kind, year, month);

  @override
  String toString() => kind == PulsePeriodKind.month
      ? 'PulsePeriod.month($year-$month)'
      : 'PulsePeriod.year($year)';
}
