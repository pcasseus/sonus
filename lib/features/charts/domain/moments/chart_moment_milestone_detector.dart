import '../entities/chart_entry.dart';
import '../entities/chart_snapshot.dart';
import 'chart_moment_event.dart';
import 'chart_moment_event_type.dart';
import 'chart_moment_longevity_state.dart';
import 'chart_moment_scope.dart';

class ChartMomentMilestoneDetector {
  const ChartMomentMilestoneDetector();

  static const List<int> weekMilestones = [1, 2, 5, 10, 20, 25, 50, 75, 100];

  static const List<int> streamMilestones = [
    10,
    25,
    50,
    100,
    250,
    500,
    1000,
    2500,
    5000,
    10000,
  ];

  List<ChartMomentEvent> detect({
    required ChartSnapshot snapshot,
    required ChartEntry entry,
    required ChartMomentLongevityState previousLongevity,
    required ChartMomentLongevityState currentLongevity,
    required int previousLifetimeStreams,
    required int currentLifetimeStreams,
    required DateTime createdAt,
    String? userId,
  }) {
    if (!snapshot.isFinalized) {
      throw ArgumentError.value(
        snapshot.finalizedAt,
        'snapshot',
        'Milestone detection requires a finalized chart snapshot.',
      );
    }

    if (previousLifetimeStreams < 0) {
      throw ArgumentError.value(
        previousLifetimeStreams,
        'previousLifetimeStreams',
        'Lifetime streams must not be negative.',
      );
    }

    if (currentLifetimeStreams < 0) {
      throw ArgumentError.value(
        currentLifetimeStreams,
        'currentLifetimeStreams',
        'Lifetime streams must not be negative.',
      );
    }

    final events = <ChartMomentEvent>[];

    _addCrossedMilestones(
      events: events,
      snapshot: snapshot,
      entry: entry,
      createdAt: createdAt,
      eventType: ChartMomentEventType.totalWeeksMilestone,
      previousValue: previousLongevity.totalChartWeeks,
      currentValue: currentLongevity.totalChartWeeks,
      milestones: weekMilestones,
      userId: userId,
    );

    _addCrossedMilestones(
      events: events,
      snapshot: snapshot,
      entry: entry,
      createdAt: createdAt,
      eventType: ChartMomentEventType.consecutiveWeeksMilestone,
      previousValue: previousLongevity.consecutiveChartWeeks,
      currentValue: currentLongevity.consecutiveChartWeeks,
      milestones: weekMilestones,
      userId: userId,
    );

    final thresholds = <int>{
      ...previousLongevity.totalThresholdWeeks.keys,
      ...previousLongevity.consecutiveThresholdWeeks.keys,
      ...currentLongevity.totalThresholdWeeks.keys,
      ...currentLongevity.consecutiveThresholdWeeks.keys,
    }.toList()..sort((a, b) => b.compareTo(a));

    for (final threshold in thresholds) {
      _addCrossedMilestones(
        events: events,
        snapshot: snapshot,
        entry: entry,
        createdAt: createdAt,
        eventType: ChartMomentEventType.totalThresholdWeeksMilestone,
        previousValue: previousLongevity.totalWeeksAt(threshold),
        currentValue: currentLongevity.totalWeeksAt(threshold),
        milestones: weekMilestones,
        threshold: threshold,
        userId: userId,
      );

      _addCrossedMilestones(
        events: events,
        snapshot: snapshot,
        entry: entry,
        createdAt: createdAt,
        eventType: ChartMomentEventType.consecutiveThresholdWeeksMilestone,
        previousValue: previousLongevity.consecutiveWeeksAt(threshold),
        currentValue: currentLongevity.consecutiveWeeksAt(threshold),
        milestones: weekMilestones,
        threshold: threshold,
        userId: userId,
      );
    }

    _addCrossedMilestones(
      events: events,
      snapshot: snapshot,
      entry: entry,
      createdAt: createdAt,
      eventType: ChartMomentEventType.lifetimeStreamMilestone,
      previousValue: previousLifetimeStreams,
      currentValue: currentLifetimeStreams,
      milestones: streamMilestones,
      userId: userId,
    );

    return List<ChartMomentEvent>.unmodifiable(events);
  }

  static void _addCrossedMilestones({
    required List<ChartMomentEvent> events,
    required ChartSnapshot snapshot,
    required ChartEntry entry,
    required DateTime createdAt,
    required ChartMomentEventType eventType,
    required int previousValue,
    required int currentValue,
    required Iterable<int> milestones,
    required String? userId,
    int? threshold,
  }) {
    for (final milestone in milestones) {
      if (previousValue >= milestone || currentValue < milestone) {
        continue;
      }

      events.add(
        _event(
          snapshot: snapshot,
          entry: entry,
          createdAt: createdAt,
          eventType: eventType,
          threshold: threshold,
          milestoneValue: milestone,
          userId: userId,
        ),
      );
    }
  }

  static ChartMomentEvent _event({
    required ChartSnapshot snapshot,
    required ChartEntry entry,
    required DateTime createdAt,
    required ChartMomentEventType eventType,
    required int milestoneValue,
    required String? userId,
    int? threshold,
  }) {
    final finalizedAt = snapshot.finalizedAt!.toUtc();

    final deduplicationKey = _deduplicationKey(
      snapshot: snapshot,
      entityId: entry.entity.entityId,
      eventType: eventType,
      threshold: threshold,
      milestoneValue: milestoneValue,
    );

    return ChartMomentEvent(
      id: deduplicationKey,
      deduplicationKey: deduplicationKey,
      userId: userId,
      sourceId: snapshot.id,
      chartType: snapshot.chartType,
      scope: ChartMomentScope.finalized,
      eventType: eventType,
      entity: entry.entity,
      weekStartUtc: snapshot.weekStartUtc.toUtc(),
      weekEndUtc: snapshot.weekEndUtc.toUtc(),
      occurredAt: finalizedAt,
      createdAt: createdAt.toUtc(),
      previousRank: entry.previousFinalRank,
      currentRank: entry.rank,
      currentPeakRank: entry.peakRank,
      qualifiedStreamCount: entry.qualifiedStreamCount,
      threshold: threshold,
      milestoneValue: milestoneValue,
    );
  }

  static String _deduplicationKey({
    required ChartSnapshot snapshot,
    required String entityId,
    required ChartMomentEventType eventType,
    required int milestoneValue,
    required int? threshold,
  }) {
    return [
      'moment',
      'finalized',
      snapshot.chartType.name,
      snapshot.weekStartUtc.toUtc().millisecondsSinceEpoch,
      entityId,
      snapshot.id,
      eventType.name,
      threshold ?? '-',
      milestoneValue,
    ].join(':');
  }
}
