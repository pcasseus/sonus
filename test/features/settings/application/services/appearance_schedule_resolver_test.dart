import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/features/settings/application/services/appearance_schedule_resolver.dart';
import 'package:sonus_next/features/settings/domain/models/appearance_preferences.dart';

import 'appearance_test_time_zones.dart';

void main() {
  AppearancePreferences scheduled({
    AppearanceClockTime day = const AppearanceClockTime(7, 0),
    AppearanceClockTime night = const AppearanceClockTime(19, 0),
  }) {
    return AppearancePreferences(
      theme: SonusThemeId.kickflip,
      schedule: AppearanceSchedule(
        enabled: true,
        dayTheme: SonusThemeId.daylight,
        nightTheme: SonusThemeId.afterHours,
        dayStartsAt: day,
        nightStartsAt: night,
      ),
    );
  }

  const utc = AppearanceScheduleResolver(
    timeZone: FixedTestZone(Duration.zero),
  );

  test('uses the manual theme while scheduling is off', () {
    final resolved = utc.resolve(
      preferences: const AppearancePreferences(theme: SonusThemeId.kickflip),
      override: null,
      now: DateTime.utc(2026, 10, 23, 12),
    );

    expect(resolved.theme, SonusThemeId.kickflip);
    expect(resolved.phase, AppearancePhase.manual);
    expect(resolved.nextTransitionAt, isNull);
  });

  group('windows', () {
    test('daytime uses the day theme until night starts', () {
      final resolved = utc.resolve(
        preferences: scheduled(),
        override: null,
        now: DateTime.utc(2026, 10, 23, 12),
      );

      expect(resolved.theme, SonusThemeId.daylight);
      expect(resolved.phase, AppearancePhase.day);
      expect(resolved.windowStartedAt, DateTime.utc(2026, 10, 23, 7));
      expect(resolved.nextTransitionAt, DateTime.utc(2026, 10, 23, 19));
    });

    test('night runs past midnight into the next morning', () {
      for (final now in [
        DateTime.utc(2026, 10, 23, 23, 30),
        DateTime.utc(2026, 10, 24, 3),
      ]) {
        final resolved = utc.resolve(
          preferences: scheduled(),
          override: null,
          now: now,
        );

        expect(resolved.theme, SonusThemeId.afterHours, reason: '$now');
        expect(resolved.windowStartedAt, DateTime.utc(2026, 10, 23, 19));
        expect(resolved.nextTransitionAt, DateTime.utc(2026, 10, 24, 7));
      }
    });

    test('the transition instant itself starts the new window', () {
      final atBoundary = utc.resolve(
        preferences: scheduled(),
        override: null,
        now: DateTime.utc(2026, 10, 23, 19),
      );
      final justBefore = utc.resolve(
        preferences: scheduled(),
        override: null,
        now: DateTime.utc(2026, 10, 23, 18, 59, 59, 999),
      );

      expect(atBoundary.phase, AppearancePhase.night);
      expect(justBefore.phase, AppearancePhase.day);
    });

    test('a night starting after midnight makes the day cross midnight', () {
      final preferences = scheduled(
        day: const AppearanceClockTime(9, 0),
        night: const AppearanceClockTime(1, 0),
      );

      AppearancePhase phaseAt(DateTime now) =>
          utc.resolve(preferences: preferences, override: null, now: now).phase;

      expect(phaseAt(DateTime.utc(2026, 10, 23, 23, 30)), AppearancePhase.day);
      expect(phaseAt(DateTime.utc(2026, 10, 24, 0, 30)), AppearancePhase.day);
      expect(phaseAt(DateTime.utc(2026, 10, 24, 1)), AppearancePhase.night);
      expect(phaseAt(DateTime.utc(2026, 10, 24, 8, 59)), AppearancePhase.night);
      expect(phaseAt(DateTime.utc(2026, 10, 24, 9)), AppearancePhase.day);
    });
  });

  group('device time', () {
    test('uses the local wall clock, not UTC', () {
      const newYork = AppearanceScheduleResolver(
        timeZone: FixedTestZone(Duration(hours: -4)),
      );

      // 18:30 local.
      final resolved = newYork.resolve(
        preferences: scheduled(),
        override: null,
        now: DateTime.utc(2026, 10, 23, 22, 30),
      );

      expect(resolved.phase, AppearancePhase.day);
      // 19:00 local.
      expect(resolved.nextTransitionAt, DateTime.utc(2026, 10, 23, 23));
    });

    test('a time-zone change moves the active window', () {
      final now = DateTime.utc(2026, 10, 23, 20);

      const london = AppearanceScheduleResolver(
        timeZone: FixedTestZone(Duration(hours: 1)),
      );
      const tokyo = AppearanceScheduleResolver(
        timeZone: FixedTestZone(Duration(hours: 9)),
      );

      // 21:00 in London, 05:00 next day in Tokyo.
      expect(
        london
            .resolve(preferences: scheduled(), override: null, now: now)
            .phase,
        AppearancePhase.night,
      );
      final inTokyo = tokyo.resolve(
        preferences: scheduled(),
        override: null,
        now: now,
      );
      expect(inTokyo.phase, AppearancePhase.night);
      expect(inTokyo.nextTransitionAt, DateTime.utc(2026, 10, 23, 22));
    });

    const eastern = AppearanceScheduleResolver(timeZone: EasternTestZone());

    test('spring forward keeps transitions at local wall-clock times', () {
      // 07:30 EDT on the day clocks went forward.
      final resolved = eastern.resolve(
        preferences: scheduled(),
        override: null,
        now: DateTime.utc(2026, 3, 8, 11, 30),
      );

      expect(resolved.phase, AppearancePhase.day);
      expect(resolved.windowStartedAt, DateTime.utc(2026, 3, 8, 11));
      expect(resolved.nextTransitionAt, DateTime.utc(2026, 3, 8, 23));
    });

    test('a start time skipped by spring forward uses the next valid time', () {
      final preferences = scheduled(day: const AppearanceClockTime(2, 30));

      // 01:59 EST: still night.
      expect(
        eastern
            .resolve(
              preferences: preferences,
              override: null,
              now: DateTime.utc(2026, 3, 8, 6, 59),
            )
            .phase,
        AppearancePhase.night,
      );

      // 03:00 EDT: 02:30 never happened, so day starts now.
      final resolved = eastern.resolve(
        preferences: preferences,
        override: null,
        now: DateTime.utc(2026, 3, 8, 7),
      );
      expect(resolved.phase, AppearancePhase.day);
      expect(resolved.windowStartedAt, DateTime.utc(2026, 3, 8, 7));
    });

    test('fall back keeps transitions at local wall-clock times', () {
      // 06:30 EST, an hour after clocks went back: still night.
      final early = eastern.resolve(
        preferences: scheduled(),
        override: null,
        now: DateTime.utc(2026, 11, 1, 11, 30),
      );
      expect(early.phase, AppearancePhase.night);
      expect(early.nextTransitionAt, DateTime.utc(2026, 11, 1, 12));

      // 07:00 EST.
      expect(
        eastern
            .resolve(
              preferences: scheduled(),
              override: null,
              now: DateTime.utc(2026, 11, 1, 12),
            )
            .phase,
        AppearancePhase.day,
      );
    });
  });

  group('override', () {
    final now = DateTime.utc(2026, 10, 23, 12);

    test('applies until the next transition', () {
      final override = AppearanceOverride(
        theme: SonusThemeId.monochrome,
        setAt: DateTime.utc(2026, 10, 23, 10),
      );

      final during = utc.resolve(
        preferences: scheduled(),
        override: override,
        now: now,
      );
      final after = utc.resolve(
        preferences: scheduled(),
        override: override,
        now: DateTime.utc(2026, 10, 23, 19),
      );

      expect(during.theme, SonusThemeId.monochrome);
      expect(during.phase, AppearancePhase.override);
      expect(during.nextTransitionAt, DateTime.utc(2026, 10, 23, 19));
      expect(after.theme, SonusThemeId.afterHours);
      expect(after.phase, AppearancePhase.night);
    });

    test('one set in an earlier window has expired', () {
      final resolved = utc.resolve(
        preferences: scheduled(),
        override: AppearanceOverride(
          theme: SonusThemeId.monochrome,
          setAt: DateTime.utc(2026, 10, 23, 6, 59),
        ),
        now: now,
      );

      expect(resolved.phase, AppearancePhase.day);
    });

    test('one set in the future (clock moved back) has expired', () {
      final resolved = utc.resolve(
        preferences: scheduled(),
        override: AppearanceOverride(
          theme: SonusThemeId.monochrome,
          setAt: DateTime.utc(2026, 10, 23, 13),
        ),
        now: now,
      );

      expect(resolved.phase, AppearancePhase.day);
    });

    test('is ignored while scheduling is off', () {
      final resolved = utc.resolve(
        preferences: const AppearancePreferences(theme: SonusThemeId.kickflip),
        override: AppearanceOverride(
          theme: SonusThemeId.monochrome,
          setAt: DateTime.utc(2026, 10, 23, 10),
        ),
        now: now,
      );

      expect(resolved.theme, SonusThemeId.kickflip);
    });
  });
}
