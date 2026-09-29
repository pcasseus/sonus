import '../models/chart_entity_snapshot.dart';
import '../models/chart_type.dart';
import 'chart_moment_event.dart';
import 'chart_moment_event_type.dart';
import 'chart_moment_rank_observation.dart';
import 'chart_moment_scope.dart';

class ChartMomentLiveDetector {
  const ChartMomentLiveDetector();

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

  List<ChartMomentEvent> detectRankTransition({
    required ChartType chartType,
    required ChartEntitySnapshot entity,
    required DateTime weekStartUtc,
    required DateTime weekEndUtc,
    required ChartMomentRankObservation observation,
    required DateTime createdAt,
    int? qualifiedStreamCount,
    String? userId,
  }) {
    final events = <ChartMomentEvent>[];

    final previousRank = observation.previousRank;
    final currentRank = observation.currentRank;
    final previousPeakRank = observation.previousPeakRank;
    final currentPeakRank = observation.currentPeakRank;

    var isLifecycleEntry = false;

    // ------------------------------------------------------------------
    // Top-200 lifecycle.
    // ------------------------------------------------------------------

    if (currentRank != null) {
      if (!observation.hadPreviousObservation) {
        // A previous finalized Top-200 position means this is merely the
        // reconstruction's first observation for an entity that was already
        // charting when the week began.
        if (observation.previousFinalizedRank == null) {
          isLifecycleEntry = true;

          events.add(
            _event(
              chartType: chartType,
              entity: entity,
              weekStartUtc: weekStartUtc,
              weekEndUtc: weekEndUtc,
              observation: observation,
              createdAt: createdAt,
              eventType: previousPeakRank == null
                  ? ChartMomentEventType.debut
                  : ChartMomentEventType.reentry,
              qualifiedStreamCount: qualifiedStreamCount,
              userId: userId,
            ),
          );
        }
      } else if (previousRank == null) {
        isLifecycleEntry = true;

        events.add(
          _event(
            chartType: chartType,
            entity: entity,
            weekStartUtc: weekStartUtc,
            weekEndUtc: weekEndUtc,
            observation: observation,
            createdAt: createdAt,
            eventType: previousPeakRank == null
                ? ChartMomentEventType.debut
                : ChartMomentEventType.reentry,
            qualifiedStreamCount: qualifiedStreamCount,
            userId: userId,
          ),
        );
      }
    }

    if (observation.exitedChart) {
      events.add(
        _event(
          chartType: chartType,
          entity: entity,
          weekStartUtc: weekStartUtc,
          weekEndUtc: weekEndUtc,
          observation: observation,
          createdAt: createdAt,
          eventType: ChartMomentEventType.chartExit,
          qualifiedStreamCount: qualifiedStreamCount,
          userId: userId,
        ),
      );
    }

    // ------------------------------------------------------------------
    // Ordinary in-chart movement.
    // ------------------------------------------------------------------

    if (observation.hadPreviousObservation &&
        previousRank != null &&
        currentRank != null &&
        previousRank != currentRank) {
      events.add(
        _event(
          chartType: chartType,
          entity: entity,
          weekStartUtc: weekStartUtc,
          weekEndUtc: weekEndUtc,
          observation: observation,
          createdAt: createdAt,
          eventType: currentRank < previousRank
              ? ChartMomentEventType.rankRise
              : ChartMomentEventType.rankFall,
          qualifiedStreamCount: qualifiedStreamCount,
          userId: userId,
        ),
      );
    }

    // ------------------------------------------------------------------
    // Threshold entrances and exits.
    //
    // First reconstruction observations only count as threshold entrances
    // when they are also genuine lifecycle entries. This prevents an entity
    // that ended last week at #143 from generating a fake Top-200 return
    // merely because reconstruction began.
    // ------------------------------------------------------------------

    for (final threshold in thresholds) {
      final enteredThreshold =
          currentRank != null &&
          currentRank <= threshold &&
          ((observation.hadPreviousObservation &&
                  (previousRank == null || previousRank > threshold)) ||
              (!observation.hadPreviousObservation && isLifecycleEntry));

      if (enteredThreshold) {
        final isFirstThresholdEntry =
            previousPeakRank == null || previousPeakRank > threshold;

        events.add(
          _event(
            chartType: chartType,
            entity: entity,
            weekStartUtc: weekStartUtc,
            weekEndUtc: weekEndUtc,
            observation: observation,
            createdAt: createdAt,
            eventType: isFirstThresholdEntry
                ? ChartMomentEventType.firstThresholdEntry
                : ChartMomentEventType.thresholdReturn,
            threshold: threshold,
            qualifiedStreamCount: qualifiedStreamCount,
            userId: userId,
          ),
        );

        if (threshold == 1) {
          events.add(
            _event(
              chartType: chartType,
              entity: entity,
              weekStartUtc: weekStartUtc,
              weekEndUtc: weekEndUtc,
              observation: observation,
              createdAt: createdAt,
              eventType: isFirstThresholdEntry
                  ? ChartMomentEventType.firstNumberOne
                  : ChartMomentEventType.returnToNumberOne,
              threshold: 1,
              qualifiedStreamCount: qualifiedStreamCount,
              userId: userId,
            ),
          );
        }
      }

      final exitedThreshold =
          observation.hadPreviousObservation &&
          previousRank != null &&
          previousRank <= threshold &&
          (currentRank == null || currentRank > threshold);

      if (exitedThreshold) {
        events.add(
          _event(
            chartType: chartType,
            entity: entity,
            weekStartUtc: weekStartUtc,
            weekEndUtc: weekEndUtc,
            observation: observation,
            createdAt: createdAt,
            eventType: ChartMomentEventType.thresholdExit,
            threshold: threshold,
            qualifiedStreamCount: qualifiedStreamCount,
            userId: userId,
          ),
        );
      }
    }

    if (observation.hadPreviousObservation &&
        previousRank == 1 &&
        currentRank != 1) {
      events.add(
        _event(
          chartType: chartType,
          entity: entity,
          weekStartUtc: weekStartUtc,
          weekEndUtc: weekEndUtc,
          observation: observation,
          createdAt: createdAt,
          eventType: ChartMomentEventType.losesNumberOne,
          threshold: 1,
          qualifiedStreamCount: qualifiedStreamCount,
          userId: userId,
        ),
      );
    }

    // ------------------------------------------------------------------
    // Peak behavior.
    // ------------------------------------------------------------------

    if (currentRank != null &&
        currentPeakRank != null &&
        (previousPeakRank == null || currentPeakRank < previousPeakRank)) {
      events.add(
        _event(
          chartType: chartType,
          entity: entity,
          weekStartUtc: weekStartUtc,
          weekEndUtc: weekEndUtc,
          observation: observation,
          createdAt: createdAt,
          eventType: ChartMomentEventType.newPeak,
          qualifiedStreamCount: qualifiedStreamCount,
          userId: userId,
        ),
      );
    } else if (observation.hadPreviousObservation &&
        previousRank != currentRank &&
        currentRank != null &&
        previousPeakRank != null &&
        currentRank == previousPeakRank &&
        currentPeakRank == previousPeakRank) {
      events.add(
        _event(
          chartType: chartType,
          entity: entity,
          weekStartUtc: weekStartUtc,
          weekEndUtc: weekEndUtc,
          observation: observation,
          createdAt: createdAt,
          eventType: ChartMomentEventType.peakMatch,
          qualifiedStreamCount: qualifiedStreamCount,
          userId: userId,
        ),
      );
    }

    return List<ChartMomentEvent>.unmodifiable(events);
  }

  static ChartMomentEvent _event({
    required ChartType chartType,
    required ChartEntitySnapshot entity,
    required DateTime weekStartUtc,
    required DateTime weekEndUtc,
    required ChartMomentRankObservation observation,
    required DateTime createdAt,
    required ChartMomentEventType eventType,
    int? threshold,
    int? qualifiedStreamCount,
    String? userId,
  }) {
    final deduplicationKey = _deduplicationKey(
      chartType: chartType,
      entityId: entity.entityId,
      weekStartUtc: weekStartUtc,
      sourceEventId: observation.sourceEventId,
      eventType: eventType,
      threshold: threshold,
      previousRank: observation.previousRank,
      currentRank: observation.currentRank,
    );

    return ChartMomentEvent(
      id: deduplicationKey,
      deduplicationKey: deduplicationKey,
      userId: userId,
      sourceId: observation.sourceEventId,
      chartType: chartType,
      scope: ChartMomentScope.live,
      eventType: eventType,
      entity: entity,
      weekStartUtc: weekStartUtc.toUtc(),
      weekEndUtc: weekEndUtc.toUtc(),
      occurredAt: observation.observedAt.toUtc(),
      createdAt: createdAt.toUtc(),
      previousRank: observation.previousRank,
      currentRank: observation.currentRank,
      threshold: threshold,
      previousPeakRank: observation.previousPeakRank,
      currentPeakRank: observation.currentPeakRank,
      qualifiedStreamCount: qualifiedStreamCount,
    );
  }

  static String _deduplicationKey({
    required ChartType chartType,
    required String entityId,
    required DateTime weekStartUtc,
    required String sourceEventId,
    required ChartMomentEventType eventType,
    required int? threshold,
    required int? previousRank,
    required int? currentRank,
  }) {
    return [
      'moment',
      'live',
      chartType.name,
      weekStartUtc.toUtc().millisecondsSinceEpoch,
      entityId,
      sourceEventId,
      eventType.name,
      threshold ?? '-',
      previousRank ?? 'out',
      currentRank ?? 'out',
    ].join(':');
  }
}
