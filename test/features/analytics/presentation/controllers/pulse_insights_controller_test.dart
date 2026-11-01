import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period.dart';
import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period_data.dart';
import 'package:sonus_next/features/analytics/application/services/pulse/pulse_entity_directory.dart';
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
      expect(c.comparisonData, isNull, reason: 'not eligible');
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

  group('P5 extras', () {
    test(
      'an eligible comparison loads its period once, for rank movement',
      () async {
        loader.previousAvailable = true;
        final c = controller();
        await c.initialize();

        expect(loader.loaded, [
          PulsePeriod.month(2026, 10),
          PulsePeriod.month(2026, 9),
        ]);
        expect(c.comparisonData!.period, PulsePeriod.month(2026, 9));

        c.setComparison(PulseComparisonChoice.none);
        expect(c.comparisonData, isNull);

        await c.previousPeriod();
        expect(
          loader.loaded.where((p) => p == PulsePeriod.month(2026, 9)),
          hasLength(1),
          reason: 'September was cached as a finished period',
        );
      },
    );

    test('names come from the directory loader after the data', () async {
      final directory = _FakeDirectory();
      final c = PulseInsightsController(
        loader: loader,
        directory: directory,
        nowLocal: () => now,
      );
      addTearDown(c.dispose);
      await c.initialize();

      expect(directory.loads, 1);
      expect(
        c.directory.infoFor(PulseEntityKind.track, 'song').title,
        'Known Song',
      );
    });

    test('a failing directory leaves neutral names, not an error', () async {
      final c = PulseInsightsController(
        loader: loader,
        directory: _FakeDirectory(fail: true),
        nowLocal: () => now,
      );
      addTearDown(c.dispose);
      await c.initialize();

      expect(c.status, PulseViewStatus.ready);
      expect(c.error, isNull);
      expect(
        c.directory.infoFor(PulseEntityKind.track, 'song').title,
        'Unknown track',
      );
    });

    test('lifetime streams are read once per item per session', () async {
      final c = controller();
      await c.initialize();

      expect(await c.lifetimeStreams(PulseEntityKind.artist, 'a'), 1234);
      expect(await c.lifetimeStreams(PulseEntityKind.artist, 'a'), 1234);
      expect(loader.lifetimeCalls, 1);
      await c.refresh();
      await c.lifetimeStreams(PulseEntityKind.artist, 'a');
      expect(loader.lifetimeCalls, 2);
    });
  });
}

class _FakeDirectory implements PulseDirectoryLoader {
  _FakeDirectory({this.fail = false});

  final bool fail;
  int loads = 0;

  @override
  Future<PulseEntityDirectory> load(PulsePeriodData data) async {
    loads++;
    if (fail) throw StateError('library unreadable');
    return PulseEntityDirectory({
      (PulseEntityKind.track, 'song'): const PulseEntityInfo(
        kind: PulseEntityKind.track,
        id: 'song',
        title: 'Known Song',
        subtitle: 'Known Artist',
        artworkPath: null,
        status: PulseEntityStatus.current,
      ),
    });
  }
}

class _FakeLoader implements PulsePeriodLoader, PulseLifetimeLoader {
  _FakeLoader(this.first);

  /// Whether the previous period is an eligible comparison. Off by
  /// default, so only the selected period loads.
  bool previousAvailable = false;
  int lifetimeCalls = 0;

  @override
  Future<int> lifetimeStreams(PulseEntityKind kind, String id) async {
    lifetimeCalls++;
    return 1234;
  }

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
        availability: previousAvailable
            ? PulseComparisonAvailability.available
            : PulseComparisonAvailability.notEnoughHistory,
        totals: previousAvailable ? PulseMetrics.zero : null,
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
