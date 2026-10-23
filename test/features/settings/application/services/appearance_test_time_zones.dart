import 'package:sonus_next/features/settings/application/services/appearance_schedule_resolver.dart';

/// A zone with a constant offset from UTC. Local wall-clock fields are
/// represented as UTC [DateTime]s, so tests never depend on the machine's
/// own time zone.
class FixedTestZone extends AppearanceTimeZone {
  const FixedTestZone(this.offset);

  final Duration offset;

  @override
  DateTime toLocal(DateTime instant) => instant.toUtc().add(offset);

  @override
  DateTime fromLocal(int year, int month, int day, int hour, int minute) {
    return DateTime.utc(year, month, day, hour, minute).subtract(offset);
  }
}

/// US Eastern time for 2026: EST (UTC-5), with EDT (UTC-4) from
/// 8 March 02:00 EST until 1 November 02:00 EDT.
class EasternTestZone extends AppearanceTimeZone {
  const EasternTestZone();

  static final _dstStart = DateTime.utc(2026, 3, 8, 7);
  static final _dstEnd = DateTime.utc(2026, 11, 1, 6);

  static Duration _offsetAt(DateTime instant) {
    final utc = instant.toUtc();
    final summer = !utc.isBefore(_dstStart) && utc.isBefore(_dstEnd);

    return Duration(hours: summer ? -4 : -5);
  }

  @override
  DateTime toLocal(DateTime instant) => instant.toUtc().add(_offsetAt(instant));

  @override
  DateTime fromLocal(int year, int month, int day, int hour, int minute) {
    final wall = DateTime.utc(year, month, day, hour, minute);

    // The earlier reading wins for a repeated (fall back) hour.
    for (final offset in const [Duration(hours: -4), Duration(hours: -5)]) {
      final candidate = wall.subtract(offset);

      if (toLocal(candidate) == wall) {
        return candidate;
      }
    }

    // A wall time skipped by spring forward starts when clocks resume.
    return _dstStart;
  }
}
