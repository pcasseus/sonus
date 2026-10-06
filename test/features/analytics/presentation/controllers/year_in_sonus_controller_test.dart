import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/application/models/analytics_behavior_metrics.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_period.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_summary.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_time_window.dart';
import 'package:sonus_next/features/analytics/application/models/year_in_sonus/year_in_sonus_recap.dart';
import 'package:sonus_next/features/analytics/application/services/year_in_sonus/year_in_sonus_service.dart';
import 'package:sonus_next/features/analytics/presentation/controllers/year_in_sonus_controller.dart';

void main() {
  group('YearInSonusController', () {
    test('starts on the current year', () {
      final controller = YearInSonusController(
        service: _FakeLoader(),
        now: () => DateTime(2026, 10, 6),
      );

      expect(controller.selectedYear, 2026);
      expect(controller.currentYear, 2026);
      expect(controller.canGoNext, isFalse);
    });

    test('loads the selected year', () async {
      final loader = _FakeLoader(results: {2026: _recap(2026)});

      final controller = YearInSonusController(
        service: loader,
        now: () => DateTime(2026, 10, 6),
      );

      await controller.load();

      expect(loader.requestedYears, [2026]);
      expect(controller.recap?.year, 2026);
      expect(controller.hasData, isTrue);
      expect(controller.hasError, isFalse);
      expect(controller.isLoading, isFalse);
    });

    test('previousYear loads the previous year', () async {
      final loader = _FakeLoader(results: {2025: _recap(2025)});

      final controller = YearInSonusController(
        service: loader,
        now: () => DateTime(2026, 10, 6),
      );

      await controller.previousYear();

      expect(controller.selectedYear, 2025);
      expect(controller.recap?.year, 2025);
      expect(controller.canGoNext, isTrue);
    });

    test('nextYear does not move beyond the current year', () async {
      final controller = YearInSonusController(
        service: _FakeLoader(),
        now: () => DateTime(2026, 10, 6),
      );

      await controller.nextYear();

      expect(controller.selectedYear, 2026);
    });

    test('selectYear clamps future years to current year', () async {
      final loader = _FakeLoader(results: {2026: _recap(2026)});

      final controller = YearInSonusController(
        service: loader,
        now: () => DateTime(2026, 10, 6),
      );

      await controller.selectYear(2030);

      expect(controller.selectedYear, 2026);
      expect(loader.requestedYears, [2026]);
    });

    test('selectYear rejects non-positive years', () async {
      final controller = YearInSonusController(
        service: _FakeLoader(),
        now: () => DateTime(2026, 10, 6),
      );

      expect(() => controller.selectYear(0), throwsArgumentError);
    });

    test('refresh preserves existing recap while refreshing', () async {
      final completer = Completer<YearInSonusRecap>();

      final loader = _FakeLoader(results: {2026: _recap(2026)});

      final controller = YearInSonusController(
        service: loader,
        now: () => DateTime(2026, 10, 6),
      );

      await controller.load();

      loader.pending = completer;

      final refreshFuture = controller.refresh();

      expect(controller.isRefreshing, isTrue);
      expect(controller.recap?.year, 2026);

      completer.complete(_recap(2026));

      await refreshFuture;

      expect(controller.isRefreshing, isFalse);
      expect(controller.hasError, isFalse);
    });

    test('exposes load errors', () async {
      final loader = _FakeLoader(error: StateError('boom'));

      final controller = YearInSonusController(
        service: loader,
        now: () => DateTime(2026, 10, 6),
      );

      await controller.load();

      expect(controller.hasError, isTrue);
      expect(controller.error, isA<StateError>());
      expect(controller.isLoading, isFalse);
    });

    test('a later request wins over a stale request', () async {
      final first = Completer<YearInSonusRecap>();
      final second = Completer<YearInSonusRecap>();

      final loader = _SequencedLoader([first, second]);

      final controller = YearInSonusController(
        service: loader,
        now: () => DateTime(2026, 10, 6),
      );

      final firstRequest = controller.selectYear(2025);
      final secondRequest = controller.selectYear(2024);

      second.complete(_recap(2024));
      await secondRequest;

      first.complete(_recap(2025));
      await firstRequest;

      expect(controller.selectedYear, 2024);
      expect(controller.recap?.year, 2024);
    });

    test('isEmpty reflects an empty annual recap', () async {
      final loader = _FakeLoader(results: {2026: _recap(2026)});

      final controller = YearInSonusController(
        service: loader,
        now: () => DateTime(2026, 10, 6),
      );

      await controller.load();

      expect(controller.isEmpty, isTrue);
    });
  });
}

YearInSonusRecap _recap(int year) {
  return YearInSonusRecap(
    year: year,
    summary: const AnalyticsSummary(
      period: AnalyticsPeriod.year,
      window: AnalyticsTimeWindow(startUtc: null, endUtc: null),
      qualifiedStreamCount: 0,
      qualifiedListeningDuration: Duration.zero,
      distinctSongCount: 0,
      distinctArtistCount: 0,
      distinctAlbumCount: 0,
      firstQualifiedAt: null,
      lastQualifiedAt: null,
    ),
    audibleListeningDuration: Duration.zero,
    behavior: const AnalyticsBehaviorMetrics(
      period: AnalyticsPeriod.year,
      window: AnalyticsTimeWindow(startUtc: null, endUtc: null),
      sessionCount: 0,
      endedSessionCount: 0,
      completedSessionCount: 0,
      skippedSessionCount: 0,
      stoppedSessionCount: 0,
      replacedSessionCount: 0,
      interruptedSessionCount: 0,
      failedSessionCount: 0,
      firstSessionStartedAt: null,
      lastSessionStartedAt: null,
      activeQualifiedDayCount: 0,
      averageQualifiedStreamsPerActiveDay: 0,
      averageQualifiedStreamsPerCalendarDay: 0,
      peakDay: null,
    ),
    topTracks: const [],
    topArtists: const [],
    topAlbums: const [],
    months: const [],
    longestListeningStreakDays: 0,
  );
}

class _FakeLoader implements YearInSonusLoader {
  _FakeLoader({this.results = const {}, this.error});

  final Map<int, YearInSonusRecap> results;
  final Object? error;

  final List<int> requestedYears = [];

  Completer<YearInSonusRecap>? pending;

  @override
  Future<YearInSonusRecap> load({required int year}) async {
    requestedYears.add(year);

    final activePending = pending;

    if (activePending != null) {
      return activePending.future;
    }

    final failure = error;

    if (failure != null) {
      throw failure;
    }

    return results[year] ?? _recap(year);
  }
}

class _SequencedLoader implements YearInSonusLoader {
  _SequencedLoader(this.completers);

  final List<Completer<YearInSonusRecap>> completers;

  var index = 0;

  @override
  Future<YearInSonusRecap> load({required int year}) {
    return completers[index++].future;
  }
}
