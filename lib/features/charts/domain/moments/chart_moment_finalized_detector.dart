import '../entities/chart_entry.dart';
import '../entities/chart_snapshot.dart';
import '../models/chart_entity_snapshot.dart';
import '../models/chart_type.dart';
import 'chart_moment_event.dart';
import 'chart_moment_event_type.dart';
import 'chart_moment_scope.dart';

class ChartMomentFinalizedDetector {
  const ChartMomentFinalizedDetector();

  static const List<int> thresholds = [
    200,
    100,
    75,
    50,
    40,
    30,
    25,
    20,
    15,
    10,
    5,
    3,
    2,
    1,
  ];

  List<ChartMomentEvent> detect({
    required ChartSnapshot snapshot,
    required Iterable<ChartSnapshot> history,
    required DateTime createdAt,
    String? userId,
  }) {
    if (!snapshot.isFinalized) {
      throw ArgumentError.value(
        snapshot.finalizedAt,
        'snapshot',
        'FINAL Moment detection requires a finalized chart snapshot.',
      );
    }

    final finalizedAt = snapshot.finalizedAt!.toUtc();
    final weekStartUtc = snapshot.weekStartUtc.toUtc();

    final earlierHistory = history
        .where(
          (historical) =>
              historical.isFinalized &&
              historical.chartType == snapshot.chartType &&
              historical.weekStartUtc.toUtc().isBefore(weekStartUtc),
        )
        .toList(growable: false);

    final previousWeeks = earlierHistory
        .where((historical) => historical.weekEndUtc.toUtc() == weekStartUtc)
        .toList(growable: false);

    if (previousWeeks.length > 1) {
      throw StateError(
        'Multiple finalized previous-week snapshots exist for '
        '${snapshot.chartType.name} at ${weekStartUtc.toIso8601String()}.',
      );
    }

    final previousSnapshot = previousWeeks.isEmpty
        ? null
        : previousWeeks.single;

    final previousByEntityId = <String, ChartEntry>{
      for (final entry in previousSnapshot?.entries ?? const <ChartEntry>[])
        entry.entity.entityId: entry,
    };

    final currentByEntityId = <String, ChartEntry>{
      for (final entry in snapshot.entries) entry.entity.entityId: entry,
    };

    final historicalPeakByEntityId = _historicalPeaks(earlierHistory);

    final historicallyChartedEntityIds = <String>{
      for (final historical in earlierHistory)
        for (final entry in historical.entries) entry.entity.entityId,
    };

    final events = <ChartMomentEvent>[];

    for (final current in snapshot.entries) {
      final entityId = current.entity.entityId;
      final previous = previousByEntityId[entityId];
      final previousPeakRank = historicalPeakByEntityId[entityId];
      final hadHistoricalAppearance = historicallyChartedEntityIds.contains(
        entityId,
      );

      if (previous == null) {
        events.add(
          _event(
            snapshot: snapshot,
            entity: current.entity,
            createdAt: createdAt,
            finalizedAt: finalizedAt,
            eventType: hadHistoricalAppearance
                ? ChartMomentEventType.reentry
                : ChartMomentEventType.debut,
            previousRank: null,
            currentRank: current.rank,
            previousPeakRank: previousPeakRank,
            currentPeakRank: current.peakRank,
            qualifiedStreamCount: current.qualifiedStreamCount,
            userId: userId,
          ),
        );
      } else {
        events.add(
          _event(
            snapshot: snapshot,
            entity: current.entity,
            createdAt: createdAt,
            finalizedAt: finalizedAt,
            eventType: current.rank < previous.rank
                ? ChartMomentEventType.rankRise
                : current.rank > previous.rank
                ? ChartMomentEventType.rankFall
                : ChartMomentEventType.rankSame,
            previousRank: previous.rank,
            currentRank: current.rank,
            previousPeakRank: previousPeakRank,
            currentPeakRank: current.peakRank,
            qualifiedStreamCount: current.qualifiedStreamCount,
            userId: userId,
          ),
        );
      }

      for (final threshold in thresholds) {
        final enteredThreshold =
            current.rank <= threshold &&
            (previous == null || previous.rank > threshold);

        if (enteredThreshold) {
          final isFirstThresholdEntry =
              previousPeakRank == null || previousPeakRank > threshold;

          events.add(
            _event(
              snapshot: snapshot,
              entity: current.entity,
              createdAt: createdAt,
              finalizedAt: finalizedAt,
              eventType: isFirstThresholdEntry
                  ? ChartMomentEventType.firstThresholdEntry
                  : ChartMomentEventType.thresholdReturn,
              previousRank: previous?.rank,
              currentRank: current.rank,
              threshold: threshold,
              previousPeakRank: previousPeakRank,
              currentPeakRank: current.peakRank,
              qualifiedStreamCount: current.qualifiedStreamCount,
              userId: userId,
            ),
          );

          if (threshold == 1) {
            events.add(
              _event(
                snapshot: snapshot,
                entity: current.entity,
                createdAt: createdAt,
                finalizedAt: finalizedAt,
                eventType: isFirstThresholdEntry
                    ? ChartMomentEventType.firstNumberOne
                    : ChartMomentEventType.returnToNumberOne,
                previousRank: previous?.rank,
                currentRank: current.rank,
                threshold: 1,
                previousPeakRank: previousPeakRank,
                currentPeakRank: current.peakRank,
                qualifiedStreamCount: current.qualifiedStreamCount,
                userId: userId,
              ),
            );
          }
        }

        final exitedThreshold =
            previous != null &&
            previous.rank <= threshold &&
            current.rank > threshold;

        if (exitedThreshold) {
          events.add(
            _event(
              snapshot: snapshot,
              entity: current.entity,
              createdAt: createdAt,
              finalizedAt: finalizedAt,
              eventType: ChartMomentEventType.thresholdExit,
              previousRank: previous.rank,
              currentRank: current.rank,
              threshold: threshold,
              previousPeakRank: previousPeakRank,
              currentPeakRank: current.peakRank,
              qualifiedStreamCount: current.qualifiedStreamCount,
              userId: userId,
            ),
          );
        }
      }

      if (previous?.rank == 1 && current.rank != 1) {
        events.add(
          _event(
            snapshot: snapshot,
            entity: current.entity,
            createdAt: createdAt,
            finalizedAt: finalizedAt,
            eventType: ChartMomentEventType.losesNumberOne,
            previousRank: 1,
            currentRank: current.rank,
            threshold: 1,
            previousPeakRank: previousPeakRank,
            currentPeakRank: current.peakRank,
            qualifiedStreamCount: current.qualifiedStreamCount,
            userId: userId,
          ),
        );
      }

      if (previousPeakRank == null || current.peakRank < previousPeakRank) {
        events.add(
          _event(
            snapshot: snapshot,
            entity: current.entity,
            createdAt: createdAt,
            finalizedAt: finalizedAt,
            eventType: ChartMomentEventType.newPeak,
            previousRank: previous?.rank,
            currentRank: current.rank,
            previousPeakRank: previousPeakRank,
            currentPeakRank: current.peakRank,
            qualifiedStreamCount: current.qualifiedStreamCount,
            userId: userId,
          ),
        );
      } else if (current.rank == previousPeakRank &&
          current.peakRank == previousPeakRank) {
        events.add(
          _event(
            snapshot: snapshot,
            entity: current.entity,
            createdAt: createdAt,
            finalizedAt: finalizedAt,
            eventType: ChartMomentEventType.peakMatch,
            previousRank: previous?.rank,
            currentRank: current.rank,
            previousPeakRank: previousPeakRank,
            currentPeakRank: current.peakRank,
            qualifiedStreamCount: current.qualifiedStreamCount,
            userId: userId,
          ),
        );
      }
    }

    for (final previous in previousByEntityId.values) {
      if (currentByEntityId.containsKey(previous.entity.entityId)) {
        continue;
      }

      final previousPeakRank =
          historicalPeakByEntityId[previous.entity.entityId] ??
          previous.peakRank;

      events.add(
        _event(
          snapshot: snapshot,
          entity: previous.entity,
          createdAt: createdAt,
          finalizedAt: finalizedAt,
          eventType: ChartMomentEventType.chartExit,
          previousRank: previous.rank,
          currentRank: null,
          previousPeakRank: previousPeakRank,
          currentPeakRank: previousPeakRank,
          userId: userId,
        ),
      );

      for (final threshold in thresholds) {
        if (previous.rank > threshold) {
          continue;
        }

        events.add(
          _event(
            snapshot: snapshot,
            entity: previous.entity,
            createdAt: createdAt,
            finalizedAt: finalizedAt,
            eventType: ChartMomentEventType.thresholdExit,
            previousRank: previous.rank,
            currentRank: null,
            threshold: threshold,
            previousPeakRank: previousPeakRank,
            currentPeakRank: previousPeakRank,
            userId: userId,
          ),
        );
      }

      if (previous.rank == 1) {
        events.add(
          _event(
            snapshot: snapshot,
            entity: previous.entity,
            createdAt: createdAt,
            finalizedAt: finalizedAt,
            eventType: ChartMomentEventType.losesNumberOne,
            previousRank: 1,
            currentRank: null,
            threshold: 1,
            previousPeakRank: previousPeakRank,
            currentPeakRank: previousPeakRank,
            userId: userId,
          ),
        );
      }
    }

    return List<ChartMomentEvent>.unmodifiable(events);
  }

  static Map<String, int> _historicalPeaks(Iterable<ChartSnapshot> history) {
    final peaks = <String, int>{};

    for (final snapshot in history) {
      for (final entry in snapshot.entries) {
        final entityId = entry.entity.entityId;
        final existing = peaks[entityId];

        if (existing == null || entry.peakRank < existing) {
          peaks[entityId] = entry.peakRank;
        }
      }
    }

    return peaks;
  }

  static ChartMomentEvent _event({
    required ChartSnapshot snapshot,
    required ChartEntitySnapshot entity,
    required DateTime createdAt,
    required DateTime finalizedAt,
    required ChartMomentEventType eventType,
    required int? previousRank,
    required int? currentRank,
    required int? previousPeakRank,
    required int? currentPeakRank,
    int? threshold,
    int? qualifiedStreamCount,
    String? userId,
  }) {
    final deduplicationKey = _deduplicationKey(
      chartType: snapshot.chartType,
      entityId: entity.entityId,
      weekStartUtc: snapshot.weekStartUtc,
      sourceId: snapshot.id,
      eventType: eventType,
      threshold: threshold,
      previousRank: previousRank,
      currentRank: currentRank,
    );

    return ChartMomentEvent(
      id: deduplicationKey,
      deduplicationKey: deduplicationKey,
      userId: userId,
      sourceId: snapshot.id,
      chartType: snapshot.chartType,
      scope: ChartMomentScope.finalized,
      eventType: eventType,
      entity: entity,
      weekStartUtc: snapshot.weekStartUtc.toUtc(),
      weekEndUtc: snapshot.weekEndUtc.toUtc(),
      occurredAt: finalizedAt,
      createdAt: createdAt.toUtc(),
      previousRank: previousRank,
      currentRank: currentRank,
      threshold: threshold,
      previousPeakRank: previousPeakRank,
      currentPeakRank: currentPeakRank,
      qualifiedStreamCount: qualifiedStreamCount,
    );
  }

  static String _deduplicationKey({
    required ChartType chartType,
    required String entityId,
    required DateTime weekStartUtc,
    required String sourceId,
    required ChartMomentEventType eventType,
    required int? threshold,
    required int? previousRank,
    required int? currentRank,
  }) {
    return [
      'moment',
      'finalized',
      chartType.name,
      weekStartUtc.toUtc().millisecondsSinceEpoch,
      entityId,
      sourceId,
      eventType.name,
      threshold ?? '-',
      previousRank ?? 'out',
      currentRank ?? 'out',
    ].join(':');
  }
}
