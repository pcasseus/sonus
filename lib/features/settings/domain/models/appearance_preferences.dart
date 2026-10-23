import 'package:flutter/foundation.dart';

import '../../../../core/design/sonus_theme_id.dart';
import '../../../../core/design/sonus_tokens.dart';
import '../../../../core/design/sonus_typography.dart';

/// A wall-clock time of day in the device's local time zone.
@immutable
class AppearanceClockTime {
  const AppearanceClockTime(this.hour, this.minute)
    : assert(hour >= 0 && hour < 24),
      assert(minute >= 0 && minute < 60);

  final int hour;
  final int minute;

  int get minutesOfDay => hour * 60 + minute;

  /// Parses minutes after midnight; null when out of range.
  static AppearanceClockTime? fromMinutes(Object? value) {
    if (value is! int || value < 0 || value >= 24 * 60) {
      return null;
    }

    return AppearanceClockTime(value ~/ 60, value % 60);
  }

  @override
  bool operator ==(Object other) =>
      other is AppearanceClockTime &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);
}

/// Day and night themes with user-chosen transition times.
@immutable
class AppearanceSchedule {
  const AppearanceSchedule({
    this.enabled = false,
    this.dayTheme = SonusThemeId.daylight,
    this.nightTheme = SonusThemeId.concreteSpray,
    this.dayStartsAt = const AppearanceClockTime(7, 0),
    this.nightStartsAt = const AppearanceClockTime(19, 0),
  });

  final bool enabled;
  final SonusThemeId dayTheme;
  final SonusThemeId nightTheme;
  final AppearanceClockTime dayStartsAt;

  /// May be earlier than [dayStartsAt]; the night window then ends the
  /// same morning.
  final AppearanceClockTime nightStartsAt;

  AppearanceSchedule copyWith({
    bool? enabled,
    SonusThemeId? dayTheme,
    SonusThemeId? nightTheme,
    AppearanceClockTime? dayStartsAt,
    AppearanceClockTime? nightStartsAt,
  }) {
    return AppearanceSchedule(
      enabled: enabled ?? this.enabled,
      dayTheme: dayTheme ?? this.dayTheme,
      nightTheme: nightTheme ?? this.nightTheme,
      dayStartsAt: dayStartsAt ?? this.dayStartsAt,
      nightStartsAt: nightStartsAt ?? this.nightStartsAt,
    );
  }

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'dayTheme': dayTheme.storageKey,
    'nightTheme': nightTheme.storageKey,
    'dayStartsAt': dayStartsAt.minutesOfDay,
    'nightStartsAt': nightStartsAt.minutesOfDay,
  };

  @override
  bool operator ==(Object other) =>
      other is AppearanceSchedule &&
      other.enabled == enabled &&
      other.dayTheme == dayTheme &&
      other.nightTheme == nightTheme &&
      other.dayStartsAt == dayStartsAt &&
      other.nightStartsAt == nightStartsAt;

  @override
  int get hashCode =>
      Object.hash(enabled, dayTheme, nightTheme, dayStartsAt, nightStartsAt);
}

/// The user's appearance choices.
///
/// Every field here is a portable user preference, intended to travel with
/// backups and cloud sync once that contract is approved. Device-specific
/// state lives in [AppearanceDeviceSettings], and the device's own
/// accessibility signals are never stored.
@immutable
class AppearancePreferences {
  const AppearancePreferences({
    this.theme = SonusThemeId.defaultTheme,
    this.typography = SonusTypographyPreset.defaultPreset,
    this.decoration = SonusDecorationIntensity.standard,
    this.schedule = const AppearanceSchedule(),
    this.highContrast = false,
    this.reduceMotion = false,
  });

  static const int version = 1;

  /// The manually selected theme, used while scheduling is off.
  final SonusThemeId theme;
  final SonusTypographyPreset typography;
  final SonusDecorationIntensity decoration;
  final AppearanceSchedule schedule;

  /// In-app accessibility choices. They add to, and never weaken, the
  /// device's own high-contrast and reduced-motion requests.
  final bool highContrast;
  final bool reduceMotion;

  AppearancePreferences copyWith({
    SonusThemeId? theme,
    SonusTypographyPreset? typography,
    SonusDecorationIntensity? decoration,
    AppearanceSchedule? schedule,
    bool? highContrast,
    bool? reduceMotion,
  }) {
    return AppearancePreferences(
      theme: theme ?? this.theme,
      typography: typography ?? this.typography,
      decoration: decoration ?? this.decoration,
      schedule: schedule ?? this.schedule,
      highContrast: highContrast ?? this.highContrast,
      reduceMotion: reduceMotion ?? this.reduceMotion,
    );
  }

  Map<String, Object> toJson() => {
    'version': version,
    'theme': theme.storageKey,
    'typography': typography.storageKey,
    'decoration': decoration.storageKey,
    'schedule': schedule.toJson(),
    'highContrast': highContrast,
    'reduceMotion': reduceMotion,
  };

  /// Reads [json] field by field. A missing or invalid field falls back to
  /// its default and is reported in [issues]; the rest are kept.
  static AppearancePreferences fromJson(
    Map<String, Object?> json,
    List<String> issues,
  ) {
    const defaults = AppearancePreferences();

    T field<T>(String name, T? parsed, T fallback) {
      if (parsed == null) {
        issues.add('preferences.$name');
        return fallback;
      }

      return parsed;
    }

    final rawSchedule = json['schedule'];
    final schedule = rawSchedule is Map<String, Object?>
        ? _scheduleFromJson(rawSchedule, issues)
        : field<AppearanceSchedule>('schedule', null, defaults.schedule);

    return AppearancePreferences(
      theme: field(
        'theme',
        SonusThemeId.fromStorageKey(json['theme']),
        defaults.theme,
      ),
      typography: field(
        'typography',
        SonusTypographyPreset.fromStorageKey(json['typography']),
        defaults.typography,
      ),
      decoration: field(
        'decoration',
        SonusDecorationIntensity.fromStorageKey(json['decoration']),
        defaults.decoration,
      ),
      schedule: schedule,
      highContrast: field(
        'highContrast',
        _bool(json['highContrast']),
        defaults.highContrast,
      ),
      reduceMotion: field(
        'reduceMotion',
        _bool(json['reduceMotion']),
        defaults.reduceMotion,
      ),
    );
  }

  static AppearanceSchedule _scheduleFromJson(
    Map<String, Object?> json,
    List<String> issues,
  ) {
    const defaults = AppearanceSchedule();
    final dayStartsAt = AppearanceClockTime.fromMinutes(json['dayStartsAt']);
    final nightStartsAt = AppearanceClockTime.fromMinutes(
      json['nightStartsAt'],
    );

    // Identical times leave no night window, so the times are unusable.
    if (dayStartsAt == null ||
        nightStartsAt == null ||
        dayStartsAt == nightStartsAt) {
      issues.add('preferences.schedule.times');
    }

    final timesValid =
        dayStartsAt != null &&
        nightStartsAt != null &&
        dayStartsAt != nightStartsAt;

    final enabled = _bool(json['enabled']);
    final dayTheme = SonusThemeId.fromStorageKey(json['dayTheme']);
    final nightTheme = SonusThemeId.fromStorageKey(json['nightTheme']);

    if (enabled == null) issues.add('preferences.schedule.enabled');
    if (dayTheme == null) issues.add('preferences.schedule.dayTheme');
    if (nightTheme == null) issues.add('preferences.schedule.nightTheme');

    return AppearanceSchedule(
      enabled: timesValid && (enabled ?? defaults.enabled),
      dayTheme: dayTheme ?? defaults.dayTheme,
      nightTheme: nightTheme ?? defaults.nightTheme,
      dayStartsAt: timesValid ? dayStartsAt : defaults.dayStartsAt,
      nightStartsAt: timesValid ? nightStartsAt : defaults.nightStartsAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppearancePreferences &&
      other.theme == theme &&
      other.typography == typography &&
      other.decoration == decoration &&
      other.schedule == schedule &&
      other.highContrast == highContrast &&
      other.reduceMotion == reduceMotion;

  @override
  int get hashCode => Object.hash(
    theme,
    typography,
    decoration,
    schedule,
    highContrast,
    reduceMotion,
  );
}

/// A manual theme choice made while scheduling is on. It applies until the
/// next scheduled transition after [setAt].
@immutable
class AppearanceOverride {
  AppearanceOverride({required this.theme, required DateTime setAt})
    : setAt = setAt.toUtc();

  final SonusThemeId theme;
  final DateTime setAt;

  @override
  bool operator ==(Object other) =>
      other is AppearanceOverride &&
      other.theme == theme &&
      other.setAt == setAt;

  @override
  int get hashCode => Object.hash(theme, setAt);
}

/// Appearance state that belongs to this device only: performance choices
/// and the transient schedule override. Never backed up or synced.
@immutable
class AppearanceDeviceSettings {
  const AppearanceDeviceSettings({
    this.lowEffects = false,
    this.scheduleOverride,
  });

  static const int version = 1;

  final bool lowEffects;
  final AppearanceOverride? scheduleOverride;

  AppearanceDeviceSettings copyWith({
    bool? lowEffects,
    AppearanceOverride? Function()? scheduleOverride,
  }) {
    return AppearanceDeviceSettings(
      lowEffects: lowEffects ?? this.lowEffects,
      scheduleOverride: scheduleOverride == null
          ? this.scheduleOverride
          : scheduleOverride(),
    );
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'lowEffects': lowEffects,
    'override': scheduleOverride == null
        ? null
        : {
            'theme': scheduleOverride!.theme.storageKey,
            'setAt': scheduleOverride!.setAt.toIso8601String(),
          },
  };

  static AppearanceDeviceSettings fromJson(
    Map<String, Object?> json,
    List<String> issues,
  ) {
    final lowEffects = _bool(json['lowEffects']);
    if (lowEffects == null) issues.add('device.lowEffects');

    AppearanceOverride? scheduleOverride;
    final rawOverride = json['override'];

    if (rawOverride is Map<String, Object?>) {
      final theme = SonusThemeId.fromStorageKey(rawOverride['theme']);
      final rawSetAt = rawOverride['setAt'];
      final setAt = rawSetAt is String ? DateTime.tryParse(rawSetAt) : null;

      if (theme != null && setAt != null) {
        scheduleOverride = AppearanceOverride(theme: theme, setAt: setAt);
      } else {
        issues.add('device.override');
      }
    } else if (rawOverride != null) {
      issues.add('device.override');
    }

    return AppearanceDeviceSettings(
      lowEffects: lowEffects ?? false,
      scheduleOverride: scheduleOverride,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppearanceDeviceSettings &&
      other.lowEffects == lowEffects &&
      other.scheduleOverride == scheduleOverride;

  @override
  int get hashCode => Object.hash(lowEffects, scheduleOverride);
}

bool? _bool(Object? value) => value is bool ? value : null;
