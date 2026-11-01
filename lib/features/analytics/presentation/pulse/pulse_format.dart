import '../../application/models/pulse/pulse_period.dart';
import '../../application/models/pulse/pulse_period_data.dart';

/// Words and numbers for Sonus Pulse (spec §3, §11). New strings are subject
/// to the wording review before release.
abstract final class PulseFormat {
  static const months = [
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
  ];
  static const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static String shortMonth(int month) => months[month - 1].substring(0, 3);

  /// 1842 → "1,842".
  static String grouped(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  static String periodTitle(PulsePeriod period) =>
      period.kind == PulsePeriodKind.month
      ? '${months[period.month - 1]} ${period.year}'
      : '${period.year}';

  /// "Tue 14 Oct 2026".
  static String day(DateTime local) =>
      '${weekdays[local.weekday - 1]} ${local.day} '
      '${shortMonth(local.month)} ${local.year}';

  /// "14 Oct".
  static String shortDay(DateTime local) =>
      '${local.day} ${shortMonth(local.month)}';

  /// Whole minutes, never rounded up past what was heard.
  static int minutes(Duration listened) => listened.inMinutes;

  /// "3 h 12 m", "45 m", "under a minute".
  static String duration(Duration listened) {
    final total = listened.inMinutes;
    if (total < 1) return 'under a minute';
    final hours = total ~/ 60;
    final rest = total % 60;
    if (hours == 0) return '$rest m';
    return rest == 0 ? '$hours h' : '$hours h $rest m';
  }

  /// The hero centre: "1,842" and "minutes listened" / "qualified streams".
  static (String, String) centre(PulseMetrics totals, PulseMeasure measure) =>
      switch (measure) {
        PulseMeasure.minutes => (
          grouped(minutes(totals.listened)),
          minutes(totals.listened) == 1
              ? 'minute listened'
              : 'minutes listened',
        ),
        PulseMeasure.streams => (
          grouped(totals.streams),
          totals.streams == 1 ? 'qualified stream' : 'qualified streams',
        ),
        PulseMeasure.allPlays => (
          grouped(totals.allPlays),
          totals.allPlays == 1 ? 'play' : 'plays',
        ),
      };

  /// "Tue 14 Oct 2026 · 192 min listened · 51 streams", plus the selected
  /// item's part when one is open.
  static String readout(
    PulseDay day, {
    String? itemName,
    PulseMetrics? item,
    PulseMeasure? measure,
  }) {
    final date = PulseFormat.day(day.localDate);
    switch (day.state) {
      case PulseDayState.future:
        return '$date · not yet';
      case PulseDayState.beforeHistory:
        return '$date · before your history starts';
      case PulseDayState.recorded:
        final m = day.metrics;
        final streams = m.streams == 1
            ? '1 stream'
            : '${grouped(m.streams)} streams';
        final base =
            '$date · ${grouped(minutes(m.listened))} min listened · $streams';
        if (itemName == null || item == null || measure == null) return base;
        final part = measure == PulseMeasure.streams
            ? (item.streams == 1
                  ? '1 stream'
                  : '${grouped(item.streams)} streams')
            : '${grouped(minutes(item.listened))} min';
        return '$base · $itemName $part';
    }
  }

  /// "The longest spoke is 14 Oct, 3 h 12 m", or null without data.
  static String? longestHint(PulsePeriodData data, PulseMeasure measure) {
    PulseDay? best;
    for (final day in data.days) {
      if (day.state != PulseDayState.recorded) continue;
      if (best == null ||
          day.metrics.valueOf(measure) > best.metrics.valueOf(measure)) {
        best = day;
      }
    }
    if (best == null || best.metrics.valueOf(measure) <= 0) return null;
    final value = measure == PulseMeasure.streams
        ? (best.metrics.streams == 1
              ? '1 stream'
              : '${grouped(best.metrics.streams)} streams')
        : duration(best.metrics.listened);
    return 'The longest spoke is ${shortDay(best.localDate)}, $value';
  }

  /// Screen-reader summary: "October 2026: 1,842 minutes across 27 recorded
  /// days; busiest day 14 October".
  static String summary(PulsePeriodData data, PulseMeasure measure) {
    final recorded = data.days
        .where((d) => d.state == PulseDayState.recorded)
        .toList();
    final (value, unit) = centre(data.totals, measure);
    final label = unit.replaceAll(' listened', '');
    final buffer = StringBuffer(
      '${periodTitle(data.period)}: $value $label across '
      '${recorded.length} recorded ${recorded.length == 1 ? 'day' : 'days'}',
    );
    PulseDay? busiest;
    for (final day in recorded) {
      if (day.metrics.valueOf(measure) <= 0) continue;
      if (busiest == null ||
          day.metrics.valueOf(measure) > busiest.metrics.valueOf(measure)) {
        busiest = day;
      }
    }
    if (busiest != null) {
      buffer.write(
        '; busiest day ${busiest.localDate.day} '
        '${months[busiest.localDate.month - 1]}',
      );
    }
    return buffer.toString();
  }
}
