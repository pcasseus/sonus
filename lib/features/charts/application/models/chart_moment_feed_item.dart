import '../../domain/models/chart_entity_snapshot.dart';
import '../../domain/models/chart_type.dart';
import '../../domain/moments/chart_moment_event.dart';
import '../../domain/moments/chart_moment_event_type.dart';
import '../../domain/moments/chart_moment_scope.dart';

enum ChartMomentFeedSubjectType { entity, artist }

class ChartMomentFeedItem {
  const ChartMomentFeedItem({
    required this.id,
    required this.subjectType,
    required this.chartType,
    required this.scope,
    required this.weekStartUtc,
    required this.weekEndUtc,
    required this.occurredAt,
    required this.entity,
    required this.events,
    required this.dominantEventType,
    this.relatedEntity,
    this.artistId,
  });

  final String id;
  final ChartMomentFeedSubjectType subjectType;

  final ChartType chartType;
  final ChartMomentScope scope;

  final DateTime weekStartUtc;
  final DateTime weekEndUtc;
  final DateTime occurredAt;

  final ChartEntitySnapshot entity;
  final ChartEntitySnapshot? relatedEntity;

  /// Stable artist identity for artist-level stories when available.
  final String? artistId;

  /// Exhaustive ledger facts represented by this display story.
  ///
  /// Feed aggregation never deletes or rewrites these events.
  final List<ChartMomentEvent> events;

  /// Highest-priority fact used by presentation to decide the main story angle.
  final ChartMomentEventType dominantEventType;

  bool contains(ChartMomentEventType type) {
    return events.any((event) => event.eventType == type);
  }

  bool get isLive => scope == ChartMomentScope.live;

  bool get isFinalized => scope == ChartMomentScope.finalized;
}
