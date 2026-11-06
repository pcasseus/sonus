import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_reactivity.dart';
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

    test('bold text is off by default and round-trips', () {
      expect(const AppearancePreferences().boldText, isFalse);

      const preferences = AppearancePreferences(boldText: true);
      final issues = <String>[];
      final json = preferences.toJson();

      expect(json['boldText'], isTrue);
      expect(AppearancePreferences.fromJson(json, issues), preferences);
      expect(issues, isEmpty);
    });

    test('a document saved before bold text existed reads it as off', () {
      final issues = <String>[];

      final decoded = AppearancePreferences.fromJson({
        'version': 1,
        'theme': 'after_hours',
        'typography': 'street_bold',
        'decoration': 'standard',
        'schedule': const AppearanceSchedule().toJson(),
        'highContrast': true,
        'reduceMotion': false,
        'someFutureField': 'ignored',
      }, issues);

      expect(decoded.boldText, isFalse);
      expect(decoded.highContrast, isTrue);
      expect(decoded.theme, SonusThemeId.afterHours);
      expect(issues, isEmpty);
    });

    test('an unreadable bold text value is reported and read as off', () {
      final issues = <String>[];

      final decoded = AppearancePreferences.fromJson({
        'boldText': 'yes',
      }, issues);

      expect(decoded.boldText, isFalse);
      expect(issues, contains('preferences.boldText'));
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

  // Themes 2.0 T1: the optional artwork-reactivity preference.
  group('reactivity preference', () {
    test('defaults to the theme and is not written until chosen', () {
      const preferences = AppearancePreferences();
      expect(preferences.reactivity, isNull);
      expect(preferences.toJson().containsKey('reactivity'), isFalse);
    });

    test('round-trips when chosen', () {
      for (final mode in SonusReactivityMode.values) {
        final issues = <String>[];
        final restored = AppearancePreferences.fromJson(
          AppearancePreferences(reactivity: mode).toJson(),
          issues,
        );
        expect(restored.reactivity, mode);
        expect(issues, isEmpty);
      }
    });

    test('a document saved before the field existed loads without issues', () {
      final json = const AppearancePreferences().toJson()..remove('reactivity');
      final issues = <String>[];
      final restored = AppearancePreferences.fromJson(json, issues);
      expect(restored.reactivity, isNull);
      expect(issues, isEmpty);
      expect(restored, const AppearancePreferences());
    });

    test('an unknown value is reported and ignored; the rest is kept', () {
      final json = {
        ...const AppearancePreferences(
          decoration: SonusDecorationIntensity.expressive,
        ).toJson(),
        'reactivity': 'vivid',
      };
      final issues = <String>[];
      final restored = AppearancePreferences.fromJson(json, issues);
      expect(restored.reactivity, isNull);
      expect(issues, ['preferences.reactivity']);
      expect(restored.decoration, SonusDecorationIntensity.expressive);
    });

    test('copyWith keeps, changes and clears it', () {
      const chosen = AppearancePreferences(
        reactivity: SonusReactivityMode.immersive,
      );
      expect(
        chosen.copyWith(highContrast: true).reactivity,
        SonusReactivityMode.immersive,
      );
      expect(
        chosen.copyWith(reactivity: SonusReactivityMode.static).reactivity,
        SonusReactivityMode.static,
      );
      expect(chosen.copyWith(followThemeReactivity: true).reactivity, isNull);
    });
  });
}
