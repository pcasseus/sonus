// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../application/models/pulse/pulse_period.dart';
import '../application/models/pulse/pulse_period_data.dart';

/// Which comparison the Pulse page shows. A year's previous period and same
/// period last year are the same, so years use [previous] or [none].
enum PulseComparisonChoice { previous, samePeriodLastYear, none }

/// What Sonus Pulse reopens with.
@immutable
class PulseSelection {
  const PulseSelection({
    required this.period,
    required this.measure,
    required this.comparison,
  });

  final PulsePeriod period;

  /// Minutes or Streams: the Pulse hero toggle (All plays is not a hero
  /// measure).
  final PulseMeasure measure;
  final PulseComparisonChoice comparison;

  PulseSelection copyWith({
    PulsePeriod? period,
    PulseMeasure? measure,
    PulseComparisonChoice? comparison,
  }) => PulseSelection(
    period: period ?? this.period,
    measure: measure ?? this.measure,
    comparison: comparison ?? this.comparison,
  );
}

typedef PulseGetString = Future<String?> Function(String key);
typedef PulseSetString = Future<void> Function(String key, String value);

/// Device-local Pulse preferences (spec §2, locked): `insights.pulse.period`
/// holds `{"v":1,"view":"month","year":2026,"month":10,"comparison":…}` and
/// `insights.pulse.measure` holds `minutes` or `streams`. Nothing here
/// touches SQLite, backups or sync. Unreadable values fall back to null
/// (the caller's defaults) and never throw.
class PulsePreferencesStore {
  PulsePreferencesStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences;

  @visibleForTesting
  PulsePreferencesStore.forTesting({
    required PulseGetString getString,
    required PulseSetString setString,
  }) : _preferences = null,
       _getStringOverride = getString,
       _setStringOverride = setString;

  static const String periodKey = 'insights.pulse.period';
  static const String measureKey = 'insights.pulse.measure';
  static const int version = 1;

  SharedPreferencesAsync? _preferences;
  PulseGetString? _getStringOverride;
  PulseSetString? _setStringOverride;

  SharedPreferencesAsync get _platform =>
      _preferences ??= SharedPreferencesAsync();

  Future<String?> _get(String key) =>
      (_getStringOverride ?? _platform.getString)(key);

  Future<void> _set(String key, String value) =>
      (_setStringOverride ?? _platform.setString)(key, value);

  /// The stored period and comparison, or null for each that is missing or
  /// unreadable.
  Future<({PulsePeriod? period, PulseComparisonChoice? comparison})>
  loadPeriod() async {
    try {
      final raw = await _get(periodKey);
      if (raw == null) return (period: null, comparison: null);
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic> || json['v'] != version) {
        return (period: null, comparison: null);
      }
      final year = json['year'];
      final month = json['month'];
      final period = switch (json['view']) {
        'month' when year is int && month is int && month >= 1 && month <= 12 =>
          PulsePeriod.month(year, month),
        'year' when year is int => PulsePeriod.year(year),
        _ => null,
      };
      final comparison = PulseComparisonChoice.values
          .where((c) => c.name == json['comparison'])
          .firstOrNull;
      return (period: period, comparison: comparison);
    } catch (error) {
      _log('Could not read the Pulse period', error);
      return (period: null, comparison: null);
    }
  }

  Future<PulseMeasure?> loadMeasure() async {
    try {
      return switch (await _get(measureKey)) {
        'minutes' => PulseMeasure.minutes,
        'streams' => PulseMeasure.streams,
        _ => null,
      };
    } catch (error) {
      _log('Could not read the Pulse measure', error);
      return null;
    }
  }

  /// Saves [selection]. A failed write is logged, never thrown: the page
  /// works the same, it just reopens on the default next time.
  Future<void> save(PulseSelection selection) async {
    final period = selection.period;
    try {
      await _set(
        periodKey,
        jsonEncode({
          'v': version,
          'view': period.kind.name,
          'year': period.year,
          if (period.kind == PulsePeriodKind.month) 'month': period.month,
          'comparison': selection.comparison.name,
        }),
      );
      await _set(measureKey, selection.measure.name);
    } catch (error) {
      _log('Could not save the Pulse selection', error);
    }
  }

  static void _log(String message, Object error) => developer.log(
    '$message: ${error.runtimeType}',
    name: 'sonus.insights',
    level: 900,
  );
}
