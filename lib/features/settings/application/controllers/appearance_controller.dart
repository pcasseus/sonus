import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme_factory.dart';
import '../../../../core/design/sonus_theme_id.dart';
import '../../../../core/design/sonus_tokens.dart';
import '../../../../core/design/sonus_typography.dart';
import '../../data/appearance_preferences_store.dart';
import '../../domain/models/appearance_preferences.dart';
import '../services/appearance_schedule_resolver.dart';

typedef AppearanceClock = DateTime Function();
typedef AppearanceTimerFactory =
    Timer Function(Duration duration, void Function() callback);
typedef AppearanceLogger = void Function(String message, {int level});

/// Owns the appearance preferences, the active theme and its schedule.
///
/// Changes apply immediately and are then saved. A failed save keeps the
/// change for this session, is logged, and is reported through [saveError].
class AppearanceController extends ChangeNotifier {
  AppearanceController({
    required this._store,
    this._resolver = const AppearanceScheduleResolver(),
    AppearanceClock? now,
    AppearanceTimerFactory? createTimer,
    AppearanceLogger? log,
    this.maxRecheckInterval = const Duration(minutes: 1),
  }) : _now = now ?? DateTime.now,
       _createTimer = createTimer ?? Timer.new,
       _log = log ?? _developerLog {
    _resolved = _resolve();
  }

  /// Upper bound between schedule checks.
  ///
  /// The recheck timer runs on a monotonic clock, so it is aimed exactly at
  /// the next transition. A time-zone change or a manual clock change moves
  /// that transition without the timer noticing; the bound catches such a
  /// jump within this interval. Each check is a few date calculations.
  final Duration maxRecheckInterval;

  final AppearancePreferencesStore _store;
  final AppearanceScheduleResolver _resolver;
  final AppearanceClock _now;
  final AppearanceTimerFactory _createTimer;
  final AppearanceLogger _log;

  AppearancePreferences _preferences = const AppearancePreferences();
  AppearanceDeviceSettings _device = const AppearanceDeviceSettings();
  bool _systemHighContrast = false;
  bool _systemReduceMotion = false;
  bool _isLoaded = false;
  Object? _saveError;
  late ResolvedAppearance _resolved;
  Timer? _recheck;
  Future<void> _pendingSave = Future<void>.value();
  bool _disposed = false;

  AppearancePreferences get preferences => _preferences;
  AppearanceDeviceSettings get device => _device;
  ResolvedAppearance get resolved => _resolved;
  bool get isLoaded => _isLoaded;
  bool get systemHighContrast => _systemHighContrast;
  bool get systemReduceMotion => _systemReduceMotion;

  /// The most recent save failure, until a later save succeeds.
  Object? get saveError => _saveError;

  bool get overrideActive => _resolved.phase == AppearancePhase.override;

  SonusAppearanceSpec get spec => SonusAppearanceSpec(
    themeId: _resolved.theme,
    typography: _preferences.typography,
    decoration: _preferences.decoration,
    highContrast: _preferences.highContrast || _systemHighContrast,
    reduceMotion: _preferences.reduceMotion || _systemReduceMotion,
    lowEffects: _device.lowEffects,
  );

  ThemeData get theme => SonusThemeFactory.build(spec);

  /// The wall-clock time of [instant] in the zone the schedule uses, so
  /// displayed transition times always match the schedule.
  DateTime toLocalTime(DateTime instant) => _resolver.timeZone.toLocal(instant);

  /// Reads stored preferences. If storage cannot be read, Sonus continues
  /// with defaults; the failure is logged and nothing is overwritten.
  Future<void> load() async {
    try {
      final snapshot = await _store.load();

      if (snapshot.issues.isNotEmpty) {
        _log(
          'Appearance preferences partly unreadable; defaults used for: '
          '${snapshot.issues.join(', ')}',
          level: 900,
        );
      }

      _preferences = snapshot.preferences;
      _device = snapshot.device;
    } catch (error, stackTrace) {
      _log(
        'Appearance preferences could not be read; using defaults. '
        'error=${error.runtimeType}\n$stackTrace',
        level: 1000,
      );
    }

    if (_disposed) {
      return;
    }

    _isLoaded = true;
    refresh();
    notifyListeners();
  }

  /// Re-evaluates the schedule. Called on resume, by the recheck timer and
  /// after every change.
  void refresh() {
    if (_disposed) {
      return;
    }

    final previousSpec = spec;
    final previousResolved = _resolved;
    _resolved = _resolve();

    // An override whose window has passed is cleared from storage too.
    if (_device.scheduleOverride != null && !overrideActive) {
      _device = _device.copyWith(scheduleOverride: () => null);
      unawaited(_save(device: true));
    }

    _scheduleRecheck();

    // A new window can keep the same theme (day and night may match), but
    // Appearance Settings still shows the phase and next transition.
    if (spec != previousSpec || _resolved != previousResolved) {
      notifyListeners();
    }
  }

  /// Combines the device's accessibility signals, which are never stored.
  void updateSystemAccessibility({
    required bool highContrast,
    required bool reduceMotion,
  }) {
    if (highContrast == _systemHighContrast &&
        reduceMotion == _systemReduceMotion) {
      return;
    }

    _systemHighContrast = highContrast;
    _systemReduceMotion = reduceMotion;
    notifyListeners();
  }

  /// Applies [theme]. With scheduling on, it overrides the schedule until
  /// the next transition; otherwise it becomes the manual theme.
  Future<void> selectTheme(SonusThemeId theme) {
    if (_preferences.schedule.enabled) {
      _device = _device.copyWith(
        scheduleOverride: () => AppearanceOverride(theme: theme, setAt: _now()),
      );
      return _apply(device: true);
    }

    _preferences = _preferences.copyWith(theme: theme);
    return _apply(preferences: true);
  }

  /// Returns to the scheduled theme before the next transition.
  Future<void> clearOverride() {
    if (_device.scheduleOverride == null) {
      return Future<void>.value();
    }

    _device = _device.copyWith(scheduleOverride: () => null);
    return _apply(device: true);
  }

  Future<void> setTypography(SonusTypographyPreset value) {
    _preferences = _preferences.copyWith(typography: value);
    return _apply(preferences: true);
  }

  Future<void> setDecoration(SonusDecorationIntensity value) {
    _preferences = _preferences.copyWith(decoration: value);
    return _apply(preferences: true);
  }

  Future<void> setHighContrast(bool value) {
    _preferences = _preferences.copyWith(highContrast: value);
    return _apply(preferences: true);
  }

  Future<void> setReduceMotion(bool value) {
    _preferences = _preferences.copyWith(reduceMotion: value);
    return _apply(preferences: true);
  }

  Future<void> setLowEffects(bool value) {
    _device = _device.copyWith(lowEffects: value);
    return _apply(device: true);
  }

  /// Any schedule change ends a running override.
  Future<void> updateSchedule(AppearanceSchedule schedule) {
    if (schedule.dayStartsAt == schedule.nightStartsAt) {
      throw ArgumentError.value(
        schedule.nightStartsAt.minutesOfDay,
        'nightStartsAt',
        'Day and night must start at different times.',
      );
    }

    _preferences = _preferences.copyWith(schedule: schedule);
    _device = _device.copyWith(scheduleOverride: () => null);
    return _apply(preferences: true, device: true);
  }

  Future<void> _apply({bool preferences = false, bool device = false}) {
    _resolved = _resolve();
    _scheduleRecheck();
    notifyListeners();
    return _save(preferences: preferences, device: device);
  }

  /// Saves in order, so the last change always wins.
  Future<void> _save({bool preferences = false, bool device = false}) {
    final preferencesSnapshot = _preferences;
    final deviceSnapshot = _device;

    final save = _pendingSave.then((_) async {
      try {
        if (preferences) {
          await _store.savePreferences(preferencesSnapshot);
        }
        if (device) {
          await _store.saveDevice(deviceSnapshot);
        }

        if (_saveError != null) {
          _saveError = null;
          if (!_disposed) notifyListeners();
        }
      } catch (error, stackTrace) {
        _log(
          'Appearance preferences could not be saved; the change applies '
          'until Sonus restarts. error=${error.runtimeType}\n$stackTrace',
          level: 1000,
        );
        _saveError = error;
        if (!_disposed) notifyListeners();
      }
    });

    _pendingSave = save;
    return save;
  }

  ResolvedAppearance _resolve() {
    return _resolver.resolve(
      preferences: _preferences,
      override: _device.scheduleOverride,
      now: _now(),
    );
  }

  void _scheduleRecheck() {
    _recheck?.cancel();
    _recheck = null;

    final next = _resolved.nextTransitionAt;

    if (_disposed || next == null) {
      return;
    }

    var delay = next.difference(_now().toUtc());

    if (delay > maxRecheckInterval) {
      delay = maxRecheckInterval;
    }

    // The resolver treats the transition instant itself as the start of the
    // new window, so the timer is aimed exactly at it. A timer that fires a
    // little early simply re-arms for the remainder.
    _recheck = _createTimer(delay.isNegative ? Duration.zero : delay, refresh);
  }

  @override
  void dispose() {
    _disposed = true;
    _recheck?.cancel();
    super.dispose();
  }

  static void _developerLog(String message, {int level = 800}) {
    developer.log(message, name: 'sonus.appearance', level: level);
  }
}
