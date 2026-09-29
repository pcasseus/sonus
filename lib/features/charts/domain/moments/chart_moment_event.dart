import '../models/chart_entity_snapshot.dart';
import '../models/chart_type.dart';
import 'chart_moment_event_type.dart';
import 'chart_moment_scope.dart';

class ChartMomentEvent {
  const ChartMomentEvent({
    required this.id,
    required this.deduplicationKey,
    required this.chartType,
    required this.scope,
    required this.eventType,
    required this.entity,
    required this.weekStartUtc,
    required this.weekEndUtc,
    required this.occurredAt,
    required this.createdAt,
    this.userId,
    this.sourceId,
    this.previousRank,
    this.currentRank,
    this.threshold,
    this.previousPeakRank,
    this.currentPeakRank,
    this.qualifiedStreamCount,
    this.milestoneValue,
    this.relatedEntity,
  });

  final String id;

  /// Stable semantic identity used to make deterministic event reconstruction
  /// idempotent without suppressing legitimate later transitions.
  final String deduplicationKey;

  /// Null while the Moment belongs only to the local Sonus installation.
  /// It can be attached to an account later.
  final String? userId;

  /// Identity of the source fact that produced this event.
  ///
  /// Live rank events use the triggering QualifiedPlay id. Finalized events
  /// can later use an appropriate finalized-chart source identity.
  final String? sourceId;

  final ChartType chartType;
  final ChartMomentScope scope;
  final ChartMomentEventType eventType;

  /// Historical identity snapshot for the primary subject.
  final ChartEntitySnapshot entity;

  /// Optional historical identity snapshot for comparison/relationship
  /// Moments such as dethroning another #1 or surpassing a prior record.
  final ChartEntitySnapshot? relatedEntity;

  final DateTime weekStartUtc;
  final DateTime weekEndUtc;

  /// When the underlying achievement or state transition occurred.
  final DateTime occurredAt;

  /// When Sonus first persisted the event.
  final DateTime createdAt;

  final int? previousRank;
  final int? currentRank;

  /// Landmark rank such as 100, 25, 10, 5, 3, 2, or 1.
  final int? threshold;

  final int? previousPeakRank;
  final int? currentPeakRank;

  final int? qualifiedStreamCount;

  /// Generic achievement quantity such as 1,000 lifetime streams or
  /// 10 chart weeks.
  final int? milestoneValue;

  int? get movementDistance {
    final previous = previousRank;
    final current = currentRank;

    if (previous == null || current == null) {
      return null;
    }

    return (previous - current).abs();
  }

  bool get isRise {
    final previous = previousRank;
    final current = currentRank;

    return previous != null && current != null && current < previous;
  }

  bool get isFall {
    final previous = previousRank;
    final current = currentRank;

    return previous != null && current != null && current > previous;
  }

  bool get isStationary {
    final previous = previousRank;
    final current = currentRank;

    return previous != null && current != null && current == previous;
  }
}
