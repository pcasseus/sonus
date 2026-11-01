import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period.dart';
import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period_data.dart';
import 'package:sonus_next/features/analytics/application/services/pulse/pulse_insights_service.dart';
import 'package:sonus_next/features/analytics/data/pulse_preferences_store.dart';
import 'package:sonus_next/features/analytics/presentation/controllers/pulse_insights_controller.dart';

void main() {
  // "Today" for every test: 31 October 2026, 15:00 local.
  final now = DateTime(2026, 10, 31, 15);
  final firstPlay = DateTime(2026, 8, 12, 9).toUtc();

  late _FakeLoader loader;
  late Map<String, String> stored;

  PulsePreferencesStore store() => PulsePreferencesStore.forTesting(
    getString: (key) async => stored[key],
    setString: (key, value) async => stored[key] = value,
  );

  PulseInsightsController controller({bool withStore = true}) {
    final c = PulseInsightsController(
      loader: loader,
      preferences: withStore ? store() : null,
      nowLocal: () => now,
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    loader = _FakeLoader(firstPlay);
    stored = {};
  });

  group('opening', () {
    test('defaults to this month, Minutes, vs previous', () async {
      final c = controller();
      expect(c.status, PulseViewStatus.initializing);

      await c.initialize();

      expect(c.selectedPeriod, PulsePeriod.month(2026, 10));
      expect(c.measure, PulseMeasure.minutes);
      expect(c.comparisonChoice, PulseComparisonChoice.previous);
      expect(c.status, PulseViewStatus.ready);
      expect(c.data!.period, PulsePeriod.month(2026, 10));
      expect(c.comparison, same(c.data!.previous));
    });

    test('restores the saved period, measure and comparison', () async {
      stored = {
        PulsePreferencesStore.periodKey: jsonEncode({
          'v': 1,
          'view': 'month',
          'year': 2026,
          'month': 9,
          'comparison': 'samePeriodLastYear',
        }),
        PulsePreferencesStore.measureKey: 'streams',
      };
      final c = controller();

      await c.initialize();

      expect(c.selectedPeriod, PulsePeriod.month(2026, 9));
      expect(c.measure, PulseMeasure.streams);
      expect(c.comparisonChoice, PulseComparisonChoice.samePeriodLastYear);
      expect(loader.loaded, [PulsePeriod.month(2026, 9)]);
    });

    test('a saved period after today clamps to now; one before history '
        'clamps to the first period', () async {
      stored[PulsePreferencesStore.periodKey] = jsonEncode({
        'v': 1,
        'view': 'month',
        'year': 2027,
        'month': 2,
      });
      final future = controller();
      await future.initialize();
      expect(future.selectedPeriod, PulsePeriod.month(2026, 10));

      stored[PulsePreferencesStore.periodKey] = jsonEncode({
        'v': 1,
        'view': 'year',
        'year': 2019,
      });
      final past = controller();
      await past.initialize();
      expect(past.selectedPeriod, PulsePeriod.year(2026));
    });

    test('unreadable saved values fall back to the defaults', () async {
      stored = {
        PulsePreferencesStore.periodKey: '{not json',
        PulsePreferencesStore.measureKey: 'allPlays',
      };
      final c = controller();

      await c.initialize();

      expect(c.selectedPeriod, PulsePeriod.month(2026, 10));
      expect(c.measure, PulseMeasure.minutes);
    });

    test('with no history at all there is nothing to load', () async {
      loader = _FakeLoader(null);
      final c = controller();

      await c.initialize();

      expect(c.status, PulseViewStatus.noHistory);
      expect(loader.loaded, isEmpty);
      expect(c.canGoPrevious, isFalse);
      expect(c.canGoNext, isFalse);
    });
  });

  group('navigation', () {
    test(
      'previous stops at the first recorded month; next stops at now',
      () async {
        final c = controller();
        await c.initialize();
        expect(c.canGoNext, isFalse);

        await c.previousPeriod();
        await c.previousPeriod();
        expect(c.selectedPeriod, PulsePeriod.month(2026, 8));
        expect(c.canGoPrevious, isFalse);

        await c.previousPeriod();
        expect(c.selectedPeriod, PulsePeriod.month(2026, 8));

        await c.nextPeriod();
        expect(c.selectedPeriod, PulsePeriod.month(2026, 9));
        expect(c.canGoNext, isTrue);
      },
    );

    test(
      'Month ↔ Year keeps the year; a past year opens on December',
      () async {
        loader = _FakeLoader(DateTime(2024, 3, 1).toUtc());
        final c = controller();
        await c.initialize();

        await c.setView(PulsePeriodKind.year);
        expect(c.selectedPeriod, PulsePeriod.year(2026));

        await c.previousPeriod();
        expect(c.selectedPeriod, PulsePeriod.year(2025));

        await c.setView(PulsePeriodKind.month);
        expect(c.selectedPeriod, PulsePeriod.month(2025, 12));

        await c.setView(PulsePeriodKind.year);
        await c.nextPeriod();
        await c.setView(PulsePeriodKind.month);
        expect(c.selectedPeriod, PulsePeriod.month(2026, 10));
      },
    );

    test('a year never offers "same period last year" separately', () async {
      final c = controller();
      await c.initialize();
      c.setComparison(PulseComparisonChoice.samePeriodLastYear);
      expect(c.comparisonChoice, PulseComparisonChoice.samePeriodLastYear);

      await c.setView(PulsePeriodKind.year);

      expect(c.comparisonChoice, PulseComparisonChoice.previous);
      c.setComparison(PulseComparisonChoice.samePeriodLastYear);
      expect(c.comparisonChoice, PulseComparisonChoice.previous);
    });

    test('changes are saved', () async {
      final c = controller();
      await c.initialize();

      await c.previousPeriod();
      c.setMeasure(PulseMeasure.streams);
      c.setComparison(PulseComparisonChoice.none);
      await pumpEventQueue();

      expect(jsonDecode(stored[PulsePreferencesStore.periodKey]!), {
        'v': 1,
        'view': 'month',
        'year': 2026,
        'month': 9,
        'comparison': 'none',
      });
      expect(stored[PulsePreferencesStore.measureKey], 'streams');
      expect(c.comparison, isNull);
    });

    test('All plays is not a Pulse measure', () async {
      final c = controller();
      await c.initialize();
      expect(() => c.setMeasure(PulseMeasure.allPlays), throwsArgumentError);
    });
  });

  group('loading', () {
    test('a late result for an earlier selection is dropped; the old data '
        'stays until the new period arrives', () async {
      final c = controller();
      await c.initialize();
      final october = c.data;

      loader.holdNext();
      final toSeptember = c.previousPeriod();
      expect(c.isLoading, isTrue);
      expect(c.data, same(october), reason: 'old spokes stay on screen');
      expect(c.isShowingSelectedPeriod, isFalse);

      loader.holdNext();
      final toAugust = c.previousPeriod();

      loader.release(PulsePeriod.month(2026, 8));
      await toAugust;
      loader.release(PulsePeriod.month(2026, 9));
      await toSeptember;

      expect(c.selectedPeriod, PulsePeriod.month(2026, 8));
      expect(c.data!.period, PulsePeriod.month(2026, 8));
      expect(c.isLoading, isFalse);
    });

    test('finished periods are cached for the session; the current period '
        'always reloads; refresh clears the cache', () async {
      final c = controller();
      await c.initialize();
      await c.previousPeriod();
      await c.nextPeriod();
      await c.previousPeriod();

      expect(loader.loaded, [
        PulsePeriod.month(2026, 10),
        PulsePeriod.month(2026, 9),
        PulsePeriod.month(2026, 10),
      ], reason: 'September came from the cache the second time');

      await c.refresh();
      expect(loader.loaded.last, PulsePeriod.month(2026, 9));
      expect(loader.loaded, hasLength(4));
    });

    test('an empty period is empty, not an error', () async {
      loader.empty.add(PulsePeriod.month(2026, 9));
      final c = controller();
      await c.initialize();

      await c.previousPeriod();

      expect(c.status, PulseViewStatus.empty);
    });

    test('a failure keeps the earlier data with an error; Try again '
        'recovers', () async {
      final c = controller();
      await c.initialize();

      loader.failing.add(PulsePeriod.month(2026, 9));
      await c.previousPeriod();

      expect(c.error, isA<StateError>());
      expect(c.status, PulseViewStatus.ready);
      expect(c.data!.period, PulsePeriod.month(2026, 10));
      expect(c.isShowingSelectedPeriod, isFalse);

      loader.failing.clear();
      await c.retry();

      expect(c.error, isNull);
      expect(c.data!.period, PulsePeriod.month(2026, 9));
    });

    test('a failure with nothing on screen is the error state', () async {
      loader.failing.add(PulsePeriod.month(2026, 10));
      final c = controller();

      await c.initialize();

      expect(c.status, PulseViewStatus.error);
    });

    test('a result arriving after dispose is ignored', () async {
      final c = PulseInsightsController(loader: loader, nowLocal: () => now);
      loader.holdNext();
      final opening = c.initialize();
      await pumpEventQueue();
      c.dispose();
      loader.release(PulsePeriod.month(2026, 10));
      await opening;
    });
  });
}

class _FakeLoader implements PulsePeriodLoader {
  _FakeLoader(this.first);

  final DateTime? first;
  final loaded = <PulsePeriod>[];
  final failing = <PulsePeriod>{};
  final empty = <PulsePeriod>{};
  final _held = <PulsePeriod, Completer<void>>{};
  var _holdNext = false;

  void holdNext() => _holdNext = true;

  void release(PulsePeriod period) => _held.remove(period)!.complete();

  @override
  Future<DateTime?> firstHistoryAt() async => first;

  @override
  Future<PulsePeriodData> load(PulsePeriod period) async {
    loaded.add(period);
    if (_holdNext) {
      _holdNext = false;
      final gate = _held[period] = Completer<void>();
      await gate.future;
    }
    if (failing.contains(period)) throw StateError('unreadable');
    final metrics = empty.contains(period)
        ? PulseMetrics.zero
        : const PulseMetrics(
            listened: Duration(minutes: 42),
            streams: 7,
            allPlays: 9,
          );
    return PulsePeriodData(
      period: period,
      firstHistoryAt: first,
      totals: metrics,
      days: const [],
      hours: const [],
      previous: PulseComparison(
        period: period.previous,
        availability: PulseComparisonAvailability.available,
        totals: PulseMetrics.zero,
      ),
      samePeriodLastYear: PulseComparison(
        period: period.samePeriodLastYear,
        availability: PulseComparisonAvailability.notEnoughHistory,
        totals: null,
      ),
      behavior: null,
      entityTotals: const {},
      entityLastActivity: const {},
      entityDays: const {},
      releasesOffRankings: const {},
    );
  }
}
