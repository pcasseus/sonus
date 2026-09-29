import '../models/chart_type.dart';
import '../moments/chart_moment_event.dart';

abstract interface class ChartMomentRepository {
  Future<void> saveAll(Iterable<ChartMomentEvent> events);

  Future<void> replaceFinalizedForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
    required Iterable<ChartMomentEvent> events,
  });

  Future<ChartMomentEvent?> getById(String id);

  Future<List<ChartMomentEvent>> getRecent({int? limit});
}
