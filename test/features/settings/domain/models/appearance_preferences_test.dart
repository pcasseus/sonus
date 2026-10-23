import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/core/design/sonus_typography.dart';
import 'package:sonus_next/features/settings/domain/models/appearance_preferences.dart';

void main() {
  group('AppearancePreferences', () {
    test('defaults to Concrete & Spray, Street Bold and Standard', () {
      const preferences = AppearancePreferences();

      expect(preferences.theme, SonusThemeId.concreteSpray);
      expect(preferences.typography, SonusTypographyPreset.streetBold);
      expect(preferences.decoration, SonusDecorationIntensity.standard);
      expect(preferences.schedule.enabled, isFalse);
      expect(preferences.highContrast, isFalse);
      expect(preferences.reduceMotion, isFalse);
    });

    test('round-trips through JSON without issues', () {
      final preferences = AppearancePreferences(
        theme: SonusThemeId.afterHours,
        typography: SonusTypographyPreset.editorial,
        decoration: SonusDecorationIntensity.expressive,
        schedule: const AppearanceSchedule(
          enabled: true,
          dayTheme: SonusThemeId.evergreen,
          nightTheme: SonusThemeId.neonMixtape,
          dayStartsAt: AppearanceClockTime(6, 30),
          nightStartsAt: AppearanceClockTime(21, 15),
        ),
        highContrast: true,
        reduceMotion: true,
      );
      final issues = <String>[];

      final decoded = AppearancePreferences.fromJson(
        preferences.toJson(),
        issues,
      );

      expect(decoded, preferences);
      expect(issues, isEmpty);
    });

    test('keeps valid fields when others are unreadable', () {
      final issues = <String>[];

      final decoded = AppearancePreferences.fromJson({
        'version': 1,
        'theme': 'kickflip',
        'typography': 'comic_sans',
        'decoration': 42,
        'schedule': 'tomorrow',
        'highContrast': 'yes',
        'reduceMotion': true,
      }, issues);

      expect(decoded.theme, SonusThemeId.kickflip);
      expect(decoded.typography, SonusTypographyPreset.defaultPreset);
      expect(decoded.decoration, SonusDecorationIntensity.standard);
      expect(decoded.schedule, const AppearanceSchedule());
      expect(decoded.highContrast, isFalse);
      expect(decoded.reduceMotion, isTrue);
      expect(
        issues,
        containsAll([
          'preferences.typography',
          'preferences.decoration',
          'preferences.schedule',
          'preferences.highContrast',
        ]),
      );
      expect(issues, isNot(contains('preferences.theme')));
    });

    test('a schedule with identical or invalid times is turned off', () {
      for (final times in [
        {'dayStartsAt': 480, 'nightStartsAt': 480},
        {'dayStartsAt': -1, 'nightStartsAt': 1200},
        {'dayStartsAt': 480, 'nightStartsAt': 24 * 60},
        {'dayStartsAt': '08:00', 'nightStartsAt': 1200},
      ]) {
        final issues = <String>[];

        final decoded = AppearancePreferences.fromJson({
          'schedule': {
            'enabled': true,
            'dayTheme': 'daylight',
            'nightTheme': 'monochrome',
            ...times,
          },
        }, issues);

        expect(decoded.schedule.enabled, isFalse, reason: '$times');
        expect(decoded.schedule.nightTheme, SonusThemeId.monochrome);
        expect(issues, contains('preferences.schedule.times'));
      }
    });
  });

  group('AppearanceClockTime', () {
    test('parses minutes after midnight', () {
      expect(
        AppearanceClockTime.fromMinutes(19 * 60 + 5),
        const AppearanceClockTime(19, 5),
      );
      expect(
        AppearanceClockTime.fromMinutes(0),
        const AppearanceClockTime(0, 0),
      );
      expect(AppearanceClockTime.fromMinutes(1440), isNull);
      expect(AppearanceClockTime.fromMinutes(null), isNull);
    });
  });

  group('AppearanceDeviceSettings', () {
    test('round-trips low effects and the schedule override', () {
      final device = AppearanceDeviceSettings(
        lowEffects: true,
        scheduleOverride: AppearanceOverride(
          theme: SonusThemeId.y2kReplay,
          setAt: DateTime.utc(2026, 10, 23, 14, 5),
        ),
      );
      final issues = <String>[];

      final decoded = AppearanceDeviceSettings.fromJson(
        device.toJson(),
        issues,
      );

      expect(decoded, device);
      expect(issues, isEmpty);
    });

    test('stores override times in UTC', () {
      final override = AppearanceOverride(
        theme: SonusThemeId.kickflip,
        setAt: DateTime(2026, 10, 23, 9),
      );

      expect(override.setAt.isUtc, isTrue);
    });

    test('drops an unreadable override', () {
      final issues = <String>[];

      final decoded = AppearanceDeviceSettings.fromJson({
        'lowEffects': false,
        'override': {'theme': 'gone', 'setAt': 'never'},
      }, issues);

      expect(decoded.scheduleOverride, isNull);
      expect(issues, ['device.override']);
    });
  });
}
