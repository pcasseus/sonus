import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/settings/application/controllers/appearance_controller.dart';
import 'package:sonus_next/features/settings/application/services/appearance_schedule_resolver.dart';
import 'package:sonus_next/features/settings/data/appearance_preferences_store.dart';
import 'package:sonus_next/features/settings/domain/models/appearance_preferences.dart';

import '../services/appearance_test_time_zones.dart';

const _schedule = AppearanceSchedule(
  enabled: true,
  dayTheme: SonusThemeId.daylight,
  nightTheme: SonusThemeId.afterHours,
);

void main() {
  late Map<String, String> storage;
  late List<(String, int)> logs;
  late _FakeTimers timers;
  late DateTime clock;
  late _MutableZone zone;
  Object? failWrites;

  AppearanceController buildController({AppearancePreferencesStore? store}) {
    final controller = AppearanceController(
      store:
          store ??
          AppearancePreferencesStore.forTesting(
            getString: (key) async => storage[key],
            setString: (key, value) async {
              final error = failWrites;
              if (error != null) throw error;
              storage[key] = value;
            },
          ),
      resolver: AppearanceScheduleResolver(timeZone: zone),
      now: () => clock,
      createTimer: timers.create,
      log: (message, {level = 800}) => logs.add((message, level)),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  void store(String key, Map<String, Object?> json) {
    storage[key] = jsonEncode(json);
  }

  Map<String, Object?> stored(String key) =>
      jsonDecode(storage[key]!) as Map<String, Object?>;

  setUp(() {
    storage = {};
    logs = [];
    timers = _FakeTimers();
    clock = DateTime.utc(2026, 10, 23, 12);
    zone = _MutableZone(Duration.zero);
    failWrites = null;
  });

  group('load', () {
    test('a fresh device uses the defaults', () async {
      final controller = buildController();

      await controller.load();

      expect(controller.isLoaded, isTrue);
      expect(controller.spec.themeId, SonusThemeId.concreteSpray);
      expect(controller.spec.decoration, SonusDecorationIntensity.standard);
      expect(logs, isEmpty);
    });

    test('applies stored preferences', () async {
      store(AppearancePreferencesStore.preferencesKey, {
        ...const AppearancePreferences(
          theme: SonusThemeId.kickflip,
          highContrast: true,
        ).toJson(),
      });
      store(AppearancePreferencesStore.deviceKey, {
        ...const AppearanceDeviceSettings(lowEffects: true).toJson(),
      });
      final controller = buildController();

      await controller.load();

      expect(controller.spec.themeId, SonusThemeId.kickflip);
      expect(controller.spec.highContrast, isTrue);
      expect(controller.spec.lowEffects, isTrue);
    });

    test(
      'unreadable storage keeps defaults, logs and overwrites nothing',
      () async {
        final writes = <String>[];
        final controller = buildController(
          store: AppearancePreferencesStore.forTesting(
            getString: (key) async => throw StateError('locked'),
            setString: (key, value) async => writes.add(key),
          ),
        );

        await controller.load();

        expect(controller.isLoaded, isTrue);
        expect(controller.spec.themeId, SonusThemeId.defaultTheme);
        expect(logs.single.$2, 1000);
        expect(logs.single.$1, isNot(contains('locked')));
        expect(writes, isEmpty);
      },
    );

    test('partly unreadable preferences are logged as a warning', () async {
      store(AppearancePreferencesStore.preferencesKey, {
        'version': 1,
        'theme': 'evergreen',
        'typography': 'wingdings',
      });
      final controller = buildController();

      await controller.load();

      expect(controller.spec.themeId, SonusThemeId.evergreen);
      expect(logs.single.$2, 900);
      expect(logs.single.$1, contains('preferences.typography'));
    });
  });

  group('changes', () {
    test('a manual theme applies immediately and is saved', () async {
      final controller = buildController();
      await controller.load();
      var notified = 0;
      controller.addListener(() => notified++);

      final saving = controller.selectTheme(SonusThemeId.neonMixtape);

      expect(controller.spec.themeId, SonusThemeId.neonMixtape);
      expect(notified, greaterThan(0));

      await saving;

      expect(
        stored(AppearancePreferencesStore.preferencesKey)['theme'],
        'neon_mixtape',
      );
      expect(
        storage.containsKey(AppearancePreferencesStore.deviceKey),
        isFalse,
      );
    });

    test('every setting persists to the right document', () async {
      final controller = buildController();
      await controller.load();

      await controller.setDecoration(SonusDecorationIntensity.expressive);
      await controller.setHighContrast(true);
      await controller.setReduceMotion(true);
      await controller.setLowEffects(true);

      final preferences = stored(AppearancePreferencesStore.preferencesKey);
      final device = stored(AppearancePreferencesStore.deviceKey);

      expect(preferences['decoration'], 'expressive');
      expect(preferences['highContrast'], isTrue);
      expect(preferences['reduceMotion'], isTrue);
      expect(device['lowEffects'], isTrue);
      expect(preferences.containsKey('lowEffects'), isFalse);
    });

    test(
      'a failed save keeps the change for the session and reports it',
      () async {
        final controller = buildController();
        await controller.load();
        failWrites = StateError('disk full');

        await controller.selectTheme(SonusThemeId.monochrome);

        expect(controller.spec.themeId, SonusThemeId.monochrome);
        expect(controller.saveError, isA<StateError>());
        expect(logs.last.$2, 1000);

        failWrites = null;
        await controller.selectTheme(SonusThemeId.daylight);

        expect(controller.saveError, isNull);
        expect(
          stored(AppearancePreferencesStore.preferencesKey)['theme'],
          'daylight',
        );
      },
    );

    test('saves run in order, so the last change wins', () async {
      final firstWrite = Completer<void>();
      var writes = 0;
      final controller = buildController(
        store: AppearancePreferencesStore.forTesting(
          getString: (key) async => storage[key],
          setString: (key, value) async {
            if (writes++ == 0) await firstWrite.future;
            storage[key] = value;
          },
        ),
      );
      await controller.load();

      final first = controller.selectTheme(SonusThemeId.kickflip);
      final second = controller.selectTheme(SonusThemeId.haze2017);
      firstWrite.complete();
      await Future.wait([first, second]);

      expect(
        stored(AppearancePreferencesStore.preferencesKey)['theme'],
        'haze_2017',
      );
    });

    test('device accessibility requests combine with in-app choices and are '
        'never stored', () async {
      final controller = buildController();
      await controller.load();

      controller.updateSystemAccessibility(
        highContrast: true,
        reduceMotion: true,
      );

      expect(controller.spec.highContrast, isTrue);
      expect(controller.spec.reduceMotion, isTrue);
      expect(controller.preferences.highContrast, isFalse);
      expect(storage, isEmpty);

      // Turning the in-app switch off cannot weaken the device's request.
      await controller.setHighContrast(false);
      expect(controller.spec.highContrast, isTrue);
    });
  });

  group('schedule', () {
    test('identical day and night times are rejected', () async {
      final controller = buildController();
      await controller.load();

      expect(
        () => controller.updateSchedule(
          _schedule.copyWith(
            dayStartsAt: const AppearanceClockTime(8, 0),
            nightStartsAt: const AppearanceClockTime(8, 0),
          ),
        ),
        throwsArgumentError,
      );
      expect(controller.preferences.schedule.enabled, isFalse);
    });

    test('a theme chosen while scheduling overrides until the next '
        'transition and is stored on this device only', () async {
      final controller = buildController();
      await controller.load();
      await controller.updateSchedule(_schedule);

      await controller.selectTheme(SonusThemeId.monochrome);

      expect(controller.overrideActive, isTrue);
      expect(controller.spec.themeId, SonusThemeId.monochrome);
      expect(controller.preferences.theme, SonusThemeId.concreteSpray);
      expect(
        stored(AppearancePreferencesStore.deviceKey)['override'],
        isA<Map<String, Object?>>(),
      );
      expect(
        stored(AppearancePreferencesStore.preferencesKey)['theme'],
        'concrete_spray',
      );
    });

    test('the recheck timer is aimed exactly at the next transition', () async {
      clock = DateTime.utc(2026, 10, 23, 18, 59, 30);
      final controller = buildController();
      await controller.load();

      await controller.updateSchedule(_schedule);

      expect(timers.active.single.duration, const Duration(seconds: 30));
    });

    test('a distant transition is rechecked within a minute', () async {
      final controller = buildController();
      await controller.load();

      await controller.updateSchedule(_schedule);

      expect(controller.maxRecheckInterval, const Duration(minutes: 1));
      expect(timers.active.single.duration, const Duration(minutes: 1));
    });

    test('the theme changes at the configured time, not later', () async {
      clock = DateTime.utc(2026, 10, 23, 18, 59, 30);
      final controller = buildController();
      await controller.load();
      await controller.updateSchedule(_schedule);
      expect(controller.spec.themeId, SonusThemeId.daylight);

      clock = clock.add(timers.active.single.duration);
      timers.active.single.fire();

      expect(clock, DateTime.utc(2026, 10, 23, 19));
      expect(controller.spec.themeId, SonusThemeId.afterHours);
      expect(controller.resolved.phase, AppearancePhase.night);
      expect(
        timers.active.single.duration,
        const Duration(minutes: 1),
        reason: 'the next transition is twelve hours away',
      );
    });

    test('a timer that fires early re-arms for the remainder', () async {
      clock = DateTime.utc(2026, 10, 23, 18, 59, 30);
      final controller = buildController();
      await controller.load();
      await controller.updateSchedule(_schedule);

      clock = DateTime.utc(2026, 10, 23, 18, 59, 59, 995);
      timers.active.single.fire();

      expect(controller.spec.themeId, SonusThemeId.daylight);
      expect(timers.active.single.duration, const Duration(milliseconds: 5));
    });

    test('a time-zone change is applied within a minute', () async {
      clock = DateTime.utc(2026, 10, 23, 17);
      final controller = buildController();
      await controller.load();
      await controller.updateSchedule(_schedule);
      expect(controller.resolved.phase, AppearancePhase.day);

      // The device moves three hours east: 20:00 local, already night.
      zone.offset = const Duration(hours: 3);
      clock = clock.add(timers.active.single.duration);
      timers.active.single.fire();

      expect(controller.resolved.phase, AppearancePhase.night);
      expect(controller.spec.themeId, SonusThemeId.afterHours);
    });

    test('an expired override is cleared from storage', () async {
      clock = DateTime.utc(2026, 10, 23, 18, 59);
      final controller = buildController();
      await controller.load();
      await controller.updateSchedule(_schedule);
      await controller.selectTheme(SonusThemeId.monochrome);

      clock = DateTime.utc(2026, 10, 23, 19);
      timers.active.single.fire();
      await pumpEventQueue();

      expect(controller.overrideActive, isFalse);
      expect(controller.spec.themeId, SonusThemeId.afterHours);
      expect(stored(AppearancePreferencesStore.deviceKey)['override'], isNull);
    });

    test('returning to the schedule clears the override', () async {
      final controller = buildController();
      await controller.load();
      await controller.updateSchedule(_schedule);
      await controller.selectTheme(SonusThemeId.monochrome);

      await controller.clearOverride();

      expect(controller.overrideActive, isFalse);
      expect(controller.spec.themeId, SonusThemeId.daylight);
    });

    test('changing the schedule ends an override', () async {
      final controller = buildController();
      await controller.load();
      await controller.updateSchedule(_schedule);
      await controller.selectTheme(SonusThemeId.monochrome);

      await controller.updateSchedule(
        _schedule.copyWith(dayTheme: SonusThemeId.evergreen),
      );

      expect(controller.overrideActive, isFalse);
      expect(controller.spec.themeId, SonusThemeId.evergreen);
    });

    test(
      'a new window is announced even when the theme stays the same',
      () async {
        clock = DateTime.utc(2026, 10, 23, 18, 59);
        final controller = buildController();
        await controller.load();
        await controller.updateSchedule(
          _schedule.copyWith(nightTheme: SonusThemeId.daylight),
        );
        var notified = 0;
        controller.addListener(() => notified++);

        clock = DateTime.utc(2026, 10, 23, 19);
        timers.active.single.fire();

        expect(controller.spec.themeId, SonusThemeId.daylight);
        expect(controller.resolved.phase, AppearancePhase.night);
        expect(notified, 1);
      },
    );

    test('turning scheduling off stops rechecking', () async {
      final controller = buildController();
      await controller.load();
      await controller.updateSchedule(_schedule);

      await controller.updateSchedule(_schedule.copyWith(enabled: false));

      expect(timers.active, isEmpty);
      expect(controller.spec.themeId, SonusThemeId.concreteSpray);
    });

    test('dispose cancels the recheck', () async {
      final controller = AppearanceController(
        store: AppearancePreferencesStore.forTesting(
          getString: (key) async => null,
          setString: (key, value) async {},
        ),
        resolver: AppearanceScheduleResolver(timeZone: zone),
        now: () => clock,
        createTimer: timers.create,
      );
      await controller.load();
      await controller.updateSchedule(_schedule);

      controller.dispose();

      expect(timers.active, isEmpty);
    });
  });
}

class _MutableZone extends AppearanceTimeZone {
  _MutableZone(this.offset);

  Duration offset;

  @override
  DateTime toLocal(DateTime instant) => FixedTestZone(offset).toLocal(instant);

  @override
  DateTime fromLocal(int year, int month, int day, int hour, int minute) {
    return FixedTestZone(offset).fromLocal(year, month, day, hour, minute);
  }
}

class _FakeTimers {
  final List<_FakeTimer> _created = [];

  List<_FakeTimer> get active => [
    for (final timer in _created)
      if (timer.isActive) timer,
  ];

  Timer create(Duration duration, void Function() callback) {
    final timer = _FakeTimer(duration, callback);
    _created.add(timer);
    return timer;
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  bool _active = true;

  void fire() {
    expect(_active, isTrue, reason: 'fired a cancelled timer');
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _active ? 0 : 1;
}
