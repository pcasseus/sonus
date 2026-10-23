import 'package:flutter/foundation.dart';

import '../../../../core/design/sonus_theme_id.dart';
import '../../domain/models/appearance_preferences.dart';

/// Converts between instants and the device's local wall clock.
///
/// The default reads the device time zone on every call, so time-zone and
/// daylight-saving changes take effect at the next evaluation. Tests inject
/// fixed zones.
class AppearanceTimeZone {
  const AppearanceTimeZone();

  /// The local wall-clock fields of [instant].
  DateTime toLocal(DateTime instant) => instant.toLocal();

  /// The instant at which the local wall clock shows the given time. A time
  /// skipped by a daylight-saving change resolves to the next valid time.
  DateTime fromLocal(int year, int month, int day, int hour, int minute) {
    return DateTime(year, month, day, hour, minute).toUtc();
  }
}

enum AppearancePhase { manual, day, night, override }

/// Which theme applies now, and why.
@immutable
class ResolvedAppearance {
  const ResolvedAppearance({
    required this.theme,
    required this.phase,
    this.windowStartedAt,
    this.nextTransitionAt,
  });

  final SonusThemeId theme;
  final AppearancePhase phase;

  /// The most recent scheduled transition, when scheduling is on.
  final DateTime? windowStartedAt;

  /// The next scheduled transition, when scheduling is on.
  final DateTime? nextTransitionAt;

  @override
  bool operator ==(Object other) =>
      other is ResolvedAppearance &&
      other.theme == theme &&
      other.phase == phase &&
      other.windowStartedAt == windowStartedAt &&
      other.nextTransitionAt == nextTransitionAt;

  @override
  int get hashCode =>
      Object.hash(theme, phase, windowStartedAt, nextTransitionAt);
}

/// Decides the active theme from preferences, an optional override and the
/// current instant. Pure and offline: it uses only the device clock.
class AppearanceScheduleResolver {
  const AppearanceScheduleResolver({
    this.timeZone = const AppearanceTimeZone(),
  });

  final AppearanceTimeZone timeZone;

  ResolvedAppearance resolve({
    required AppearancePreferences preferences,
    required AppearanceOverride? override,
    required DateTime now,
  }) {
    final schedule = preferences.schedule;

    if (!schedule.enabled) {
      return ResolvedAppearance(
        theme: preferences.theme,
        phase: AppearancePhase.manual,
      );
    }

    final window = _window(schedule, now.toUtc());

    if (overrideIsActive(override, window.startedAt, now)) {
      return ResolvedAppearance(
        theme: override!.theme,
        phase: AppearancePhase.override,
        windowStartedAt: window.startedAt,
        nextTransitionAt: window.nextAt,
      );
    }

    return ResolvedAppearance(
      theme: window.isDay ? schedule.dayTheme : schedule.nightTheme,
      phase: window.isDay ? AppearancePhase.day : AppearancePhase.night,
      windowStartedAt: window.startedAt,
      nextTransitionAt: window.nextAt,
    );
  }

  /// An override lasts until the first transition after it was set. One set
  /// in the future (the clock moved back) is treated as expired.
  bool overrideIsActive(
    AppearanceOverride? override,
    DateTime windowStartedAt,
    DateTime now,
  ) {
    if (override == null) {
      return false;
    }

    final setAt = override.setAt;
    return !setAt.isAfter(now.toUtc()) && !setAt.isBefore(windowStartedAt);
  }

  ({bool isDay, DateTime startedAt, DateTime nextAt}) _window(
    AppearanceSchedule schedule,
    DateTime now,
  ) {
    final local = timeZone.toLocal(now);
    final transitions = <({DateTime at, bool isDay})>[];

    // Yesterday, today and tomorrow always contain the transition before
    // and after now, whatever the order of the two daily times.
    for (var offset = -1; offset <= 1; offset++) {
      // Date arithmetic in UTC avoids daylight-saving hour shifts.
      final date = DateTime.utc(local.year, local.month, local.day + offset);

      for (final (time, isDay) in [
        (schedule.dayStartsAt, true),
        (schedule.nightStartsAt, false),
      ]) {
        transitions.add((
          at: timeZone.fromLocal(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          ),
          isDay: isDay,
        ));
      }
    }

    transitions.sort((a, b) => a.at.compareTo(b.at));

    final started = transitions.lastWhere((t) => !t.at.isAfter(now));
    final next = transitions.firstWhere((t) => t.at.isAfter(now));

    return (isDay: started.isDay, startedAt: started.at, nextAt: next.at);
  }
}
