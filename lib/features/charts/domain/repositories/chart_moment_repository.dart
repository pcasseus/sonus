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
}
