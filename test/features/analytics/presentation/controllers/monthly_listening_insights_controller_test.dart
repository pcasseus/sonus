import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/application/models/analytics_behavior_metrics.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_period.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_summary.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_time_window.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_entity_listening_durations.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_listening_distribution.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_listening_insights.dart';
import 'package:sonus_next/features/analytics/application/services/monthly_insights/monthly_listening_insights_service.dart';
import 'package:sonus_next/features/analytics/presentation/controllers/monthly_listening_insights_controller.dart';

void main() {
  group('MonthlyListeningInsightsController', () {
    test('starts on current month', () {
      final controller = MonthlyListeningInsightsController(
        service: FakeMonthlyListeningInsightsService(),
        now: () => DateTime(2026, 10, 6),
      );

      expect(controller.selectedMonth, DateTime(2026, 10));

      expect(controller.currentMonth, DateTime(2026, 10));

      expect(controller.canGoNext, isFalse);
    });

    test('loads selected month', () async {
      final service = FakeMonthlyListeningInsightsService();

      final controller = MonthlyListeningInsightsController(
        service: service,
        now: () => DateTime(2026, 10, 6),
      );

      await controller.load();

      expect(service.references, [DateTime(2026, 10)]);
      expect(controller.insights?.selectedMonth, DateTime(2026, 10));
      expect(controller.hasData, isTrue);
      expect(controller.hasError, isFalse);
      expect(controller.isLoading, isFalse);
    });

    test('moves to previous month', () async {
      final service = FakeMonthlyListeningInsightsService();

      final controller = MonthlyListeningInsightsController(
        service: service,
        now: () => DateTime(2026, 10, 6),
      );

      await controller.load();
      await controller.previousMonth();

      expect(controller.selectedMonth, DateTime(2026, 9));
      expect(controller.canGoNext, isTrue);

      expect(service.references, [DateTime(2026, 10), DateTime(2026, 9)]);
    });

    test('clears the previous snapshot while a new month loads', () async {
      final service = ControlledMonthlyListeningInsightsService();

      final controller = MonthlyListeningInsightsController(
        service: service,
        now: () => DateTime(2026, 10, 6),
      );

      final octoberLoad = controller.load();

      service.completeNext(snapshot(DateTime(2026, 10), streamCount: 10));

      await octoberLoad;

      expect(controller.insights?.selectedMonth, DateTime(2026, 10));

      final septemberLoad = controller.previousMonth();

      expect(controller.selectedMonth, DateTime(2026, 9));
      expect(controller.isLoading, isTrue);
      expect(controller.insights, isNull);
      expect(controller.presentationData, isNull);

      service.completeNext(snapshot(DateTime(2026, 9), streamCount: 9));

      await septemberLoad;

      expect(controller.isLoading, isFalse);
      expect(controller.insights?.selectedMonth, DateTime(2026, 9));
      expect(controller.insights?.currentSummary.qualifiedStreamCount, 9);
    });
    test('moves forward after moving backward', () async {
      final service = FakeMonthlyListeningInsightsService();

      final controller = MonthlyListeningInsightsController(
        service: service,
        now: () => DateTime(2026, 10, 6),
      );

      await controller.previousMonth();
      await controller.nextMonth();

      expect(controller.selectedMonth, DateTime(2026, 10));
      expect(controller.canGoNext, isFalse);
    });

    test('does not navigate into future month', () async {
      final service = FakeMonthlyListeningInsightsService();

      final controller = MonthlyListeningInsightsController(
        service: service,
        now: () => DateTime(2026, 10, 6),
      );

      await controller.nextMonth();

      expect(controller.selectedMonth, DateTime(2026, 10));
      expect(service.references, isEmpty);
    });

    test('clamps direct future month selection to current month', () async {
      final service = FakeMonthlyListeningInsightsService();

      final controller = MonthlyListeningInsightsController(
        service: service,
        now: () => DateTime(2026, 10, 6),
      );

      await controller.selectMonth(DateTime(2027, 4));

      expect(controller.selectedMonth, DateTime(2026, 10));
      expect(service.references, [DateTime(2026, 10)]);
    });

    test('refresh keeps current snapshot visible while refreshing', () async {
      final service = ControlledMonthlyListeningInsightsService();

      final controller = MonthlyListeningInsightsController(
        service: service,
        now: () => DateTime(2026, 10, 6),
      );

      final firstLoad = controller.load();

      service.completeNext(snapshot(DateTime(2026, 10)));

      await firstLoad;

      expect(controller.hasData, isTrue);

      final refresh = controller.refresh();

      expect(controller.isRefreshing, isTrue);
      expect(controller.isLoading, isFalse);
      expect(controller.hasData, isTrue);

      service.completeNext(snapshot(DateTime(2026, 10), streamCount: 99));

      await refresh;

      expect(controller.isRefreshing, isFalse);
      expect(controller.insights?.currentSummary.qualifiedStreamCount, 99);
    });

    test('exposes load errors', () async {
      final service = FakeMonthlyListeningInsightsService(
        error: StateError('boom'),
      );

      final controller = MonthlyListeningInsightsController(
        service: service,
        now: () => DateTime(2026, 10, 6),
      );

      await controller.load();

      expect(controller.hasError, isTrue);
      expect(controller.error, isA<StateError>());
      expect(controller.isLoading, isFalse);
    });

    test('newer month request wins over stale older request', () async {
      final service = ControlledMonthlyListeningInsightsService();

      final controller = MonthlyListeningInsightsController(
        service: service,
        now: () => DateTime(2026, 10, 6),
      );

      final octoberLoad = controller.load();

      final septemberLoad = controller.previousMonth();

      expect(service.references, [DateTime(2026, 10), DateTime(2026, 9)]);

      service.completeAt(1, snapshot(DateTime(2026, 9), streamCount: 9));

      await septemberLoad;

      service.completeAt(0, snapshot(DateTime(2026, 10), streamCount: 10));

      await octoberLoad;

      expect(controller.selectedMonth, DateTime(2026, 9));
      expect(controller.insights?.selectedMonth, DateTime(2026, 9));
      expect(controller.insights?.currentSummary.qualifiedStreamCount, 9);
    });
  });
}

class FakeMonthlyListeningInsightsService
    implements MonthlyListeningInsightsLoader {
  FakeMonthlyListeningInsightsService({this.error});

  final Object? error;

  final List<DateTime> references = [];

  @override
  Future<MonthlyListeningInsights> load({
    required DateTime referenceLocal,
  }) async {
    references.add(DateTime(referenceLocal.year, referenceLocal.month));

    final pendingError = error;

    if (pendingError != null) {
      throw pendingError;
    }

    return snapshot(referenceLocal);
  }
}

class ControlledMonthlyListeningInsightsService
    implements MonthlyListeningInsightsLoader {
  final List<DateTime> references = [];

  final List<Completer<MonthlyListeningInsights>> completers = [];

  @override
  Future<MonthlyListeningInsights> load({required DateTime referenceLocal}) {
    references.add(DateTime(referenceLocal.year, referenceLocal.month));

    final completer = Completer<MonthlyListeningInsights>();

    completers.add(completer);

    return completer.future;
  }

  void completeNext(MonthlyListeningInsights value) {
    final completer = completers.firstWhere(
      (candidate) => !candidate.isCompleted,
    );

    completer.complete(value);
  }

  void completeAt(int index, MonthlyListeningInsights value) {
    completers[index].complete(value);
  }
}

MonthlyListeningInsights snapshot(DateTime month, {int streamCount = 1}) {
  final selected = DateTime(month.year, month.month);

  final previous = DateTime(selected.year, selected.month - 1);

  final currentWindow = AnalyticsTimeWindow(
    startUtc: selected.toUtc(),
    endUtc: DateTime(selected.year, selected.month + 1).toUtc(),
  );

  final previousWindow = AnalyticsTimeWindow(
    startUtc: previous.toUtc(),
    endUtc: selected.toUtc(),
  );

  return MonthlyListeningInsights(
    selectedMonth: selected,
    previousMonth: previous,
    currentSummary: AnalyticsSummary(
      period: AnalyticsPeriod.month,
      window: currentWindow,
      qualifiedStreamCount: streamCount,
      qualifiedListeningDuration: Duration(minutes: streamCount),
      distinctSongCount: streamCount == 0 ? 0 : 1,
      distinctArtistCount: streamCount == 0 ? 0 : 1,
      distinctAlbumCount: streamCount == 0 ? 0 : 1,
      firstQualifiedAt: streamCount == 0 ? null : selected.toUtc(),
      lastQualifiedAt: streamCount == 0 ? null : selected.toUtc(),
    ),
    previousSummary: AnalyticsSummary(
      period: AnalyticsPeriod.month,
      window: previousWindow,
      qualifiedStreamCount: 0,
      qualifiedListeningDuration: Duration.zero,
      distinctSongCount: 0,
      distinctArtistCount: 0,
      distinctAlbumCount: 0,
      firstQualifiedAt: null,
      lastQualifiedAt: null,
    ),
    currentAudibleListeningDuration: Duration(minutes: streamCount),
    previousAudibleListeningDuration: Duration.zero,
    behavior: AnalyticsBehaviorMetrics(
      period: AnalyticsPeriod.month,
      window: currentWindow,
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
    distribution: const MonthlyListeningDistribution(days: [], hours: []),
    entityListeningDurations: const MonthlyEntityListeningDurations(
      songs: {},
      artists: {},
      albums: {},
    ),
    songs: const [],
    artists: const [],
    albums: const [],
  );
}
