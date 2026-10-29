import '../models/chart_type.dart';
import '../moments/chart_moment_event.dart';

abstract interface class ChartMomentRepository {
  Future<void> saveAll(Iterable<ChartMomentEvent> events);

  /// Publishes a finalized week's Moments once. Returns false, writing
  /// nothing, when that week's finalized Moments are already published:
  /// published Moments are never replaced or removed.
  Future<bool> publishFinalizedForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
    required Iterable<ChartMomentEvent> events,
  });

  Future<ChartMomentEvent?> getById(String id);

  Future<List<ChartMomentEvent>> getRecent({int? limit});

  /// Up to [limit] stored Moments older than [before] (from the newest
  /// without it), newest first: by occurred time, then id, like
  /// [getRecent].
  Future<List<ChartMomentEvent>> getPage({
    ChartMomentPageCursor? before,
    required int limit,
  });
}

/// The last Moment of a page: the next page starts after it.
class ChartMomentPageCursor {
  const ChartMomentPageCursor({required this.occurredAt, required this.id});

  ChartMomentPageCursor.of(ChartMomentEvent event)
    : this(occurredAt: event.occurredAt.toUtc(), id: event.id);

  final DateTime occurredAt;
  final String id;
}
