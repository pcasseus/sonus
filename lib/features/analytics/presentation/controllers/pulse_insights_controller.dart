// ignore_for_file: prefer_initializing_formals

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../../application/models/pulse/pulse_period.dart';
import '../../application/models/pulse/pulse_period_data.dart';
import '../../application/services/pulse/pulse_insights_service.dart';
import '../../data/pulse_preferences_store.dart';

/// What the Pulse page should show (spec §8).
enum PulseViewStatus {
  /// Restoring the saved selection and reading where history starts.
  initializing,

  /// Nothing recorded yet: "Listen to something and your Pulse starts here."
  noHistory,

  /// No data for the selected period yet (first load).
  loading,

  /// The selected period has no listening ("No listening recorded in …").
  empty,

  ready,

  /// Loading failed and there is nothing earlier to keep on screen.
  error,
}

/// Sonus Pulse state: the selected period, measure and comparison; loading
/// with a generation counter so late results are dropped; and a session
/// cache of finished periods (the current period always reloads, since it
/// still changes).
class PulseInsightsController extends ChangeNotifier {
  PulseInsightsController({
    required PulsePeriodLoader loader,
    PulsePreferencesStore? preferences,
    DateTime Function()? nowLocal,
  }) : _loader = loader,
       _preferences = preferences,
       _nowLocal = nowLocal ?? DateTime.now {
    _selection = PulseSelection(
      period: PulsePeriod.containing(PulsePeriodKind.month, _nowLocal()),
      measure: PulseMeasure.minutes,
      comparison: PulseComparisonChoice.previous,
    );
  }

  final PulsePeriodLoader _loader;
  final PulsePreferencesStore? _preferences;
  final DateTime Function() _nowLocal;

  late PulseSelection _selection;
  bool _initialized = false;
  bool _historyKnown = false;
  DateTime? _firstHistoryAt;

  PulsePeriodData? _data;
  bool _isLoading = false;
  Object? _error;
  int _generation = 0;
  bool _disposed = false;
  final Map<PulsePeriod, PulsePeriodData> _cache = {};

  PulseSelection get selection => _selection;
  PulsePeriod get selectedPeriod => _selection.period;
  PulseMeasure get measure => _selection.measure;
  PulseComparisonChoice get comparisonChoice => _selection.comparison;

  /// The first recorded session (UTC), once known; null with no history.
  DateTime? get firstHistoryAt => _firstHistoryAt;

  /// The data on screen. During a period change it stays the previous
  /// period's until the new one arrives (spec §8), and it stays after a
  /// failed load; check [isShowingSelectedPeriod].
  PulsePeriodData? get data => _data;

  bool get isShowingSelectedPeriod => _data?.period == _selection.period;
  bool get isLoading => _isLoading;

  /// The last load's error, also when earlier data is still shown (the
  /// page's small banner).
  Object? get error => _error;

  PulseViewStatus get status {
    if (!_initialized) {
      return _error != null
          ? PulseViewStatus.error
          : PulseViewStatus.initializing;
    }
    if (_historyKnown && _firstHistoryAt == null) {
      return PulseViewStatus.noHistory;
    }
    final data = _data;
    if (data == null) {
      return _error != null ? PulseViewStatus.error : PulseViewStatus.loading;
    }
    if (isShowingSelectedPeriod && data.totals.isEmpty) {
      return PulseViewStatus.empty;
    }
    return PulseViewStatus.ready;
  }

  PulsePeriod get _currentPeriod =>
      PulsePeriod.containing(_selection.period.kind, _nowLocal());

  PulsePeriod? get _firstPeriod {
    final first = _firstHistoryAt;
    return first == null
        ? null
        : PulsePeriod.containing(_selection.period.kind, first.toLocal());
  }

  bool get canGoPrevious {
    final first = _firstPeriod;
    return first != null &&
        !_selection.period.previous.startLocal.isBefore(first.startLocal);
  }

  bool get canGoNext =>
      _selection.period.startLocal.isBefore(_currentPeriod.startLocal);

  /// The comparison chosen for the shown period, or null for "No
  /// comparison" or before data arrives. Check its availability: one that
  /// starts before history is "partial history".
  PulseComparison? get comparison {
    final data = _data;
    if (data == null || !isShowingSelectedPeriod) return null;
    return switch (_selection.comparison) {
      PulseComparisonChoice.previous => data.previous,
      PulseComparisonChoice.samePeriodLastYear => data.samePeriodLastYear,
      PulseComparisonChoice.none => null,
    };
  }

  /// Restores the saved selection, clamps it to recorded history and
  /// today, and loads it.
  Future<void> initialize() async {
    if (_initialized) return;
    final store = _preferences;
    if (store != null) {
      final stored = await store.loadPeriod();
      final measure = await store.loadMeasure();
      _selection = _selection.copyWith(
        period: stored.period,
        comparison: stored.comparison,
        measure: measure,
      );
    }
    final generation = ++_generation;
    try {
      _firstHistoryAt = await _loader.firstHistoryAt();
      _historyKnown = true;
    } catch (error, stackTrace) {
      if (generation != _generation) return;
      _fail(error, stackTrace);
      return;
    }
    if (generation != _generation || _disposed) return;
    _initialized = true;
    _selection = _normalized(_selection);
    if (_firstHistoryAt == null) {
      _notify();
      return;
    }
    await _load();
  }

  Future<void> previousPeriod() async {
    if (!canGoPrevious) return;
    await selectPeriod(_selection.period.previous);
  }

  Future<void> nextPeriod() async {
    if (!canGoNext) return;
    await selectPeriod(_selection.period.next);
  }

  /// Shows [period], clamped to between the first recorded period and now.
  Future<void> selectPeriod(PulsePeriod period) async {
    final next = _normalized(_selection.copyWith(period: period));
    if (next.period == _selection.period && isShowingSelectedPeriod) return;
    _selection = next;
    _save();
    await _load();
  }

  /// Switches between Month and Year. A month becomes its year; a year
  /// becomes the current month if it is this year, else its December, then
  /// clamped.
  Future<void> setView(PulsePeriodKind kind) async {
    final period = _selection.period;
    if (period.kind == kind) return;
    final now = _nowLocal();
    final target = switch (kind) {
      PulsePeriodKind.year => PulsePeriod.year(period.year),
      PulsePeriodKind.month =>
        period.year == now.year
            ? PulsePeriod.month(now.year, now.month)
            : PulsePeriod.month(period.year, 12),
    };
    _selection = _normalized(_selection.copyWith(period: target));
    _save();
    await _load();
  }

  /// The hero measure: Minutes or Streams only.
  void setMeasure(PulseMeasure measure) {
    if (measure == PulseMeasure.allPlays) {
      throw ArgumentError.value(
        measure,
        'measure',
        'All plays is a tile and ranking metric, not a Pulse measure.',
      );
    }
    if (measure == _selection.measure) return;
    _selection = _selection.copyWith(measure: measure);
    _save();
    _notify();
  }

  void setComparison(PulseComparisonChoice choice) {
    final next = _normalized(_selection.copyWith(comparison: choice));
    if (next.comparison == _selection.comparison) return;
    _selection = next;
    _save();
    _notify();
  }

  /// Reloads from history: clears the session cache and re-reads where
  /// history starts (it changes after a restore or the first play).
  Future<void> refresh() async {
    _cache.clear();
    final generation = ++_generation;
    try {
      _firstHistoryAt = await _loader.firstHistoryAt();
      _historyKnown = true;
      _initialized = true;
    } catch (error, stackTrace) {
      if (generation != _generation) return;
      _fail(error, stackTrace);
      return;
    }
    if (generation != _generation || _disposed) return;
    _selection = _normalized(_selection);
    if (_firstHistoryAt == null) {
      _data = null;
      _error = null;
      _notify();
      return;
    }
    await _load();
  }

  /// "Try again" after an error.
  Future<void> retry() => _initialized ? refresh() : initialize();

  PulseSelection _normalized(PulseSelection selection) {
    var period = selection.period;
    final current = PulsePeriod.containing(period.kind, _nowLocal());
    if (period.startLocal.isAfter(current.startLocal)) period = current;
    final first = _firstHistoryAt;
    if (first != null) {
      final firstPeriod = PulsePeriod.containing(period.kind, first.toLocal());
      if (period.startLocal.isBefore(firstPeriod.startLocal)) {
        period = firstPeriod;
      }
    } else if (_historyKnown) {
      period = current;
    }
    final comparison =
        period.kind == PulsePeriodKind.year &&
            selection.comparison == PulseComparisonChoice.samePeriodLastYear
        ? PulseComparisonChoice.previous
        : selection.comparison;
    return selection.copyWith(period: period, comparison: comparison);
  }

  Future<void> _load() async {
    final period = _selection.period;
    final generation = ++_generation;
    final cached = _cache[period];
    if (cached != null) {
      _data = cached;
      _error = null;
      _isLoading = false;
      _notify();
      return;
    }
    _isLoading = true;
    _error = null;
    _notify();
    try {
      final data = await _loader.load(period);
      if (generation != _generation || _disposed) return;
      // Only finished periods are cached; the current one keeps changing.
      if (!period.endLocal.isAfter(_nowLocal())) _cache[period] = data;
      _data = data;
      _isLoading = false;
      _notify();
    } catch (error, stackTrace) {
      if (generation != _generation || _disposed) return;
      _fail(error, stackTrace);
    }
  }

  void _fail(Object error, StackTrace stackTrace) {
    developer.log(
      'Sonus Pulse could not load: ${error.runtimeType}',
      name: 'sonus.insights',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
    _error = error;
    _isLoading = false;
    _notify();
  }

  void _save() {
    final store = _preferences;
    if (store != null) store.save(_selection);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
